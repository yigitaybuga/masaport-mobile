import Foundation
import Observation

/// Rezervasyon akışının ihtiyaç duyduğu mekan bilgisi (liste veya detaydan gelir).
struct ReservationContext: Hashable {
    let venueId: Int
    let listingId: Int
    let listingSlug: String
    let name: String
    let subtitle: String
    let image: String?
    let address: String?
    let phone: String?
    let latitude: Double?
    let longitude: Double?
}

@MainActor
@Observable
final class ReservationViewModel {
    enum Step: Int { case slot, details, done }

    enum Outcome: Equatable {
        case confirmed(SavedReservation, message: String?)
        case handedOffToWeb(URL)
        case hostedCheckout(url: URL, paymentId: String)
    }

    let context: ReservationContext

    var step: Step = .slot
    var date: Date
    var guestCount: Int
    var selectedSlot: SlotOption?

    var name: String
    var phone: String
    var email: String
    var note = ""
    var kvkkAccepted = false
    var rememberMe: Bool

    private(set) var availability: VenueAvailability?
    private(set) var isLoadingAvailability = false
    private(set) var availabilityError: String?
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    private(set) var outcome: Outcome?

    private let api: PublicAPI
    private let preferences: PreferencesStore
    private let canPayInApp: Bool
    private var loadedKey: String?

    init(
        context: ReservationContext,
        initialDate: Date,
        initialGuests: Int,
        initialTime: String?,
        preloadedAvailability: VenueAvailability?,
        preferences: PreferencesStore,
        canPayInApp: Bool,
        account: CustomerAccount? = nil,
        api: PublicAPI = .shared
    ) {
        self.context = context
        self.api = api
        self.preferences = preferences
        self.canPayInApp = canPayInApp
        date = initialDate
        guestCount = initialGuests
        availability = preloadedAvailability
        // Giriş yapılmışsa hesap bilgileri önceliklidir; hatırlanan misafir bilgisi yedektir.
        name = account?.name ?? preferences.guest.name
        phone = account?.phone ?? preferences.guest.phone
        email = account?.email ?? preferences.guest.email
        rememberMe = preferences.rememberGuest
        if let preloadedAvailability {
            loadedKey = "\(DateFormat.apiDay.string(from: initialDate))-\(initialGuests)"
            if let initialTime {
                selectedSlot = preloadedAvailability.slotOptions(for: initialDate).first { $0.slot.startTime.shortTime == initialTime.shortTime && $0.isBookable }
            }
        }
        pendingInitialTime = selectedSlot == nil ? initialTime : nil
    }

    private var pendingInitialTime: String?

    var slotOptions: [SlotOption] { availability?.slotOptions(for: date) ?? [] }
    var kvkkText: VenueText? { availability?.kvkkText }
    var timeSummary: String {
        [Format.relativeDay(date), selectedSlot?.slot.startTime.shortTime, Format.guests(guestCount)].compactMap { $0 }.joined(separator: " · ")
    }

    var isNameValid: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 }
    var isPhoneValid: Bool { phone.filter(\.isNumber).count >= 10 }
    /// Klavyeden gelen boşluk, parantez ve tire gibi karakterleri temizler; başta artı işaretini korur.
    var normalizedPhone: String {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        return trimmed.hasPrefix("+") ? "+\(digits)" : digits
    }
    var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 6
    }
    var canSubmit: Bool { isNameValid && isPhoneValid && isEmailValid && kvkkAccepted && selectedSlot != nil && !isSubmitting }

    /// Ön ödeme isteyen slotlarda kart bilgisi gerektiğinden akış web'e devredilir.
    var requiresWebHandoff: Bool {
        selectedSlot?.slot.prepaymentRequired == true && !canPayInApp
    }

    func loadAvailability(force: Bool = false) async {
        let key = "\(DateFormat.apiDay.string(from: date))-\(guestCount)"
        if !force, loadedKey == key, availability != nil { return }
        loadedKey = key
        isLoadingAvailability = true
        availabilityError = nil
        defer { isLoadingAvailability = false }
        do {
            let day = DateFormat.apiDay.string(from: date)
            availability = try await api.venueAvailability(venueId: context.venueId, startDate: day, endDate: day, guestCount: guestCount)
            if let pendingInitialTime {
                selectedSlot = slotOptions.first { $0.slot.startTime.shortTime == pendingInitialTime.shortTime && $0.isBookable }
                self.pendingInitialTime = nil
            } else if let selected = selectedSlot {
                selectedSlot = slotOptions.first { $0.id == selected.id && $0.isBookable }
            }
        } catch {
            availabilityError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func continueToDetails() {
        guard selectedSlot != nil else { return }
        if requiresWebHandoff {
            outcome = .handedOffToWeb(webHandoffURL)
            return
        }
        step = .details
    }

    var webHandoffURL: URL {
        AppConfiguration.webReservationURL(
            venueID: context.venueId,
            date: DateFormat.apiDay.string(from: date),
            startTime: selectedSlot?.slot.startTime.shortTime,
            guestCount: guestCount
        )
    }

    func submit() async {
        guard let slot = selectedSlot, canSubmit else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        if rememberMe {
            preferences.rememberGuest = true
            preferences.guest = .init(name: name.trimmingCharacters(in: .whitespaces), phone: normalizedPhone, email: email.trimmingCharacters(in: .whitespaces))
        } else {
            preferences.rememberGuest = false
        }

        let request = ReservationRequest(
            venueId: context.venueId,
            customerName: name.trimmingCharacters(in: .whitespaces),
            customerPhone: normalizedPhone,
            customerEmail: email.trimmingCharacters(in: .whitespaces),
            reservationDate: DateFormat.apiDay.string(from: date),
            guestCount: guestCount,
            timeSlotId: slot.id,
            note: note.nilIfBlank,
            kvkkConsent: true
        )

        do {
            let created = try await api.createReservation(request)
            if created.needsPayment {
                if let checkout = created.checkoutUrl.flatMap(URL.init(string:)), let paymentId = created.paymentId {
                    outcome = .hostedCheckout(url: checkout, paymentId: paymentId)
                } else {
                    outcome = .handedOffToWeb(webHandoffURL)
                }
                return
            }
            let saved = makeSavedReservation(slot: slot, created: created)
            outcome = .confirmed(saved, message: created.bookingMessage?.nilIfBlank)
            step = .done
        } catch let error as APIError {
            if error.statusCode == 400, error.message.localizedCaseInsensitiveContains("payment") {
                outcome = .handedOffToWeb(webHandoffURL)
                return
            }
            submitError = error.detail ?? error.message
            if error.statusCode == 409 {
                await loadAvailability(force: true)
            }
        } catch {
            submitError = error.localizedDescription
        }
    }

    /// Ödeme tamamlandığında (hosted checkout) yerel kaydı oluşturur.
    func makeSavedReservation(slot: SlotOption, created: ReservationCreated?) -> SavedReservation {
        let start = combine(date: date, time: created?.startTime ?? slot.slot.startTime)
        let end = (created?.endTime ?? slot.slot.endTime).map { combine(date: date, time: $0) }
        return SavedReservation(
            id: UUID(),
            kind: .restaurant,
            remoteId: created?.reservationId,
            remoteUUID: created?.reservationUuid,
            title: context.name,
            subtitle: context.subtitle,
            image: context.image,
            startDate: start,
            endDate: end,
            timeText: (created?.startTime ?? slot.slot.startTime).shortTime,
            guestCount: guestCount,
            status: created?.reservationStatus ?? (slot.slot.isRequestOnly ? "PENDING" : "CONFIRMED"),
            customerName: name.trimmingCharacters(in: .whitespaces),
            note: note.nilIfBlank,
            venueId: context.venueId,
            listingSlug: context.listingSlug,
            eventId: nil,
            address: context.address,
            phone: context.phone,
            latitude: context.latitude,
            longitude: context.longitude,
            createdAt: .now
        )
    }

    private func combine(date: Date, time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.istanbul.dateComponents([.year, .month, .day], from: date)
        components.hour = parts.first ?? 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.istanbul.date(from: components) ?? date
    }

    func pollPayment(paymentId: String) async -> PaymentStatus? {
        for _ in 0..<20 {
            if let status = try? await api.paymentStatus(paymentId: paymentId), status.isFinal {
                return status
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return nil
    }
}

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

    /// Ödeme tamamlanana kadar API'de tutulan masa bekletmesi (5 dakika).
    struct PendingHold: Equatable {
        let id: Int
        let uuid: String
        let venueId: Int
        let date: String
        let startTime: String
        let guestCount: Int
        let startedAt: Date

        /// Ödeme web'de tamamlanınca bekletmeden oluşan rezervasyon hesaba bağlanır;
        /// "Rezervasyonlarım" listesinde mekan, tarih, saat ve kişi sayısıyla bulunur.
        func matches(_ reservation: CustomerReservation) -> Bool {
            guard reservation.kind == "restaurant",
                  reservation.venue?.id == venueId,
                  reservation.reservationDate == date,
                  (reservation.startTime ?? "").shortTime == startTime.shortTime,
                  reservation.guestCount == guestCount,
                  ["PENDING", "CONFIRMED"].contains((reservation.status ?? "").uppercased()) else { return false }
            // Aynı saatte daha önce yapılmış başka bir rezervasyonla karışmasın; saat farkı için iki dakika pay.
            // Oluşturma zamanı yoksa eşleşmiş sayılır: şüphede bekletme bırakılmaz.
            guard let created = reservation.createdAt.flatMap(ISO8601Parser.date(from:)) else { return true }
            return created >= startedAt.addingTimeInterval(-120)
        }
    }

    /// Bekletmenin akıbeti sorgulandığında: rezervasyon bulundu, bulunamadı veya liste okunamadı.
    enum HoldLookup {
        case completed(CustomerReservation)
        case notCompleted
        case unknown
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
    var occasion: ReservationOccasion?
    /// Bu rezervasyon için seçilen tercihler; hesap tercihleri ön seçili gelir.
    var dietary: Set<String>
    var seating: Set<String>
    var kvkkAccepted = false
    var rememberMe: Bool

    private(set) var availability: VenueAvailability?
    private(set) var isLoadingAvailability = false
    private(set) var availabilityError: String?
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    private(set) var outcome: Outcome?
    /// Web veya hosted ödeme sayfası kapandıktan sonra sonucu doğrularken.
    private(set) var isCheckingPayment = false
    /// Ödeme sayfası kapandıktan sonra gösterilen bilgi (tamamlanmadı, doğrulanamadı…).
    private(set) var paymentNotice: String?
    /// Giriş yapılmış kullanıcının web ödemesine devredilen bekletmesi; sayfa kapanınca akıbeti sorgulanır.
    private(set) var pendingHold: PendingHold?

    private let api: PublicAPI
    private let preferences: PreferencesStore
    private let canPayInApp: Bool
    private let account: CustomerAccount?
    private let holdReleaseGrace: Duration
    private var loadedKey: String?
    /// Hosted ödeme sayfasıyla başlatılan bekletme; ödeme kesin başarısız olursa bırakılır.
    private var checkoutHold: PendingHold?

    init(
        context: ReservationContext,
        initialDate: Date,
        initialGuests: Int,
        initialTime: String?,
        preloadedAvailability: VenueAvailability?,
        preferences: PreferencesStore,
        canPayInApp: Bool,
        account: CustomerAccount? = nil,
        api: PublicAPI = .shared,
        holdReleaseGrace: Duration = .seconds(10)
    ) {
        self.context = context
        self.api = api
        self.preferences = preferences
        self.canPayInApp = canPayInApp
        self.account = account
        self.holdReleaseGrace = holdReleaseGrace
        date = initialDate
        guestCount = initialGuests
        availability = preloadedAvailability
        // Giriş yapılmışsa hesap bilgileri önceliklidir; hatırlanan misafir bilgisi yedektir.
        name = account?.name ?? preferences.guest.name
        phone = account?.phone ?? preferences.guest.phone
        email = account?.email ?? preferences.guest.email
        dietary = Set(account?.preferences?.dietary ?? [])
        seating = Set(account?.preferences?.seating ?? [])
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

    /// Seçenek sırasıyla (sunucu da aynı sırayı korur) yalnızca seçili tercihler.
    var selectedGuestPreferences: CustomerPreferences {
        CustomerPreferences(
            dietary: CustomerPreferences.dietaryOptions.map(\.key).filter(dietary.contains),
            seating: CustomerPreferences.seatingOptions.map(\.key).filter(seating.contains)
        )
    }

    var guestRequestCount: Int {
        (occasion == nil ? 0 : 1) + dietary.count + seating.count + (note.nilIfBlank == nil ? 0 : 1)
    }

    func toggleOccasion(_ value: ReservationOccasion) {
        occasion = occasion == value ? nil : value
    }

    func toggleDietary(_ key: String) {
        if dietary.contains(key) { dietary.remove(key) } else { dietary.insert(key) }
    }

    func toggleSeating(_ key: String) {
        if seating.contains(key) { seating.remove(key) } else { seating.insert(key) }
    }

    /// Her seçenek, o tarihte geçerli kural uygulanmış slotu taşır (bkz. `VenueAvailability.slotOptions`).
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
    var canSubmit: Bool { isNameValid && isPhoneValid && isEmailValid && kvkkAccepted && selectedSlot != nil && !isSubmitting && !isCheckingPayment }

    /// Seçili saat ön ödeme veya kart provizyonu istiyor mu (onaylı taleplerde ödeme alınmaz).
    var requiresPrepayment: Bool {
        selectedSlot?.slot.requiresPrepayment == true && selectedSlot?.slot.isRequestOnly != true
    }

    /// Ön ödeme isteyen slotlarda kart bilgisi gerektiğinden akış web'e devredilir.
    var requiresWebHandoff: Bool { requiresPrepayment && !canPayInApp }

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
                // Tarihe özel kural (tutar, provizyon, onay) değişmiş olabilir; seçimi güncel slotla yenile.
                selectedSlot = slotOptions.first { $0.id == selected.id && $0.isBookable }
            }
        } catch {
            availabilityError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func continueToDetails() {
        guard selectedSlot != nil else { return }
        paymentNotice = nil
        step = .details
    }

    var webHandoffURL: URL {
        webHandoffURL(hold: nil)
    }

    private func webHandoffURL(hold: ReservationCreated?) -> URL {
        AppConfiguration.webReservationURL(
            venueID: context.venueId,
            date: DateFormat.apiDay.string(from: date),
            guestCount: guestCount,
            slot: selectedSlot?.slot,
            customerName: name.trimmingCharacters(in: .whitespaces),
            customerPhone: normalizedPhone,
            customerEmail: email.trimmingCharacters(in: .whitespaces),
            note: note,
            occasion: occasion?.rawValue,
            guestPreferences: selectedGuestPreferences,
            paymentOnly: requiresWebHandoff,
            reservationHoldID: hold?.reservationHoldId,
            reservationHoldUUID: hold?.reservationHoldUuid,
            holdExpiresAt: hold?.holdExpiresAt
        )
    }

    func submit() async {
        guard let slot = selectedSlot, canSubmit else { return }
        isSubmitting = true
        submitError = nil
        paymentNotice = nil
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
            occasion: occasion?.rawValue,
            guestPreferences: selectedGuestPreferences,
            kvkkConsent: true
        )

        if requiresWebHandoff {
            guard account != nil else {
                outcome = .handedOffToWeb(webHandoffURL)
                return
            }
            await submitWithHold(request, slot: slot)
            return
        }

        do {
            let created = try await api.createReservation(request)
            if created.needsPayment {
                if let checkout = created.checkoutUrl.flatMap(URL.init(string:)), let paymentId = created.paymentId {
                    checkoutHold = makePendingHold(from: created, slot: slot)
                    outcome = .hostedCheckout(url: checkout, paymentId: paymentId)
                } else {
                    outcome = .handedOffToWeb(webHandoffURL)
                }
                return
            }
            confirm(makeSavedReservation(slot: slot, created: created), message: created.bookingMessage?.nilIfBlank)
        } catch let error as APIError {
            // Tarihe özel kural uygulamanın bildiğinden farklıysa sunucu kart bilgisi ister (`requiresPayment`).
            if error.requestsCardPayment {
                if account != nil {
                    await submitWithHold(request, slot: slot)
                } else {
                    outcome = .handedOffToWeb(webHandoffURL)
                }
                return
            }
            await handleSubmitError(error)
        } catch {
            submitError = error.localizedDescription
        }
    }

    /// Giriş yapılmış kullanıcı: bilgiler API'de doğrulanır, masa hesaba bağlı olarak bekletilir ve
    /// yalnızca kart adımı güvenli web sayfasına devredilir.
    private func submitWithHold(_ base: ReservationRequest, slot: SlotOption) async {
        var request = base
        request.paymentHandoff = true
        do {
            let handoff = try await api.createReservation(request)
            if handoff.requiresPayment == true, let hold = makePendingHold(from: handoff, slot: slot) {
                pendingHold = hold
                outcome = .handedOffToWeb(webHandoffURL(hold: handoff))
                return
            }
            confirm(makeSavedReservation(slot: slot, created: handoff), message: handoff.bookingMessage?.nilIfBlank)
        } catch let error as APIError {
            // Oturum bu arada düştüyse hesapsız web akışıyla devam edilir.
            if error.code == "CUSTOMER_AUTH_REQUIRED" {
                outcome = .handedOffToWeb(webHandoffURL)
                return
            }
            await handleSubmitError(error)
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func handleSubmitError(_ error: APIError) async {
        submitError = error.detail ?? error.message
        if error.statusCode == 409 || error.code == "SLOT_NOT_AVAILABLE" {
            await loadAvailability(force: true)
        }
    }

    private func confirm(_ saved: SavedReservation, message: String?) {
        outcome = .confirmed(saved, message: message)
        step = .done
    }

    private func makePendingHold(from created: ReservationCreated, slot: SlotOption) -> PendingHold? {
        guard let id = created.reservationHoldId, let uuid = created.reservationHoldUuid?.nilIfBlank else { return nil }
        return PendingHold(
            id: id,
            uuid: uuid,
            venueId: context.venueId,
            date: DateFormat.apiDay.string(from: date),
            startTime: slot.slot.startTime,
            guestCount: guestCount,
            startedAt: .now
        )
    }

    // MARK: Ödeme sayfası kapandığında

    /// Web ödeme sayfası (bekletmeli devir) kapandığında çağrılır. Ödeme tamamlandıysa rezervasyon
    /// gösterilir; tamamlanmadıysa bekletme kısa bir süre sonra bırakılır, masa başkalarına açılır.
    func resolveWebPayment() async {
        guard let hold = pendingHold else { return }
        pendingHold = nil
        outcome = nil
        isCheckingPayment = true
        let lookup = await Self.lookUp(hold, api: api)
        isCheckingPayment = false
        switch lookup {
        case .completed(let reservation):
            confirm(makeSavedReservation(remote: reservation), message: completionMessage)
        case .notCompleted:
            paymentNotice = "Ödeme tamamlanmadı. Hazır olduğunda yeniden ödemeye geçebilirsin."
            releaseHold(hold)
        case .unknown:
            // Sonuç doğrulanamadıysa bekletmeye dokunulmaz; süresi dolunca kendiliğinden kalkar.
            paymentNotice = "Ödeme durumunu şu anda doğrulayamadık. Rezervasyonun tamamlandıysa Rezervasyonlar sekmesinde görünür."
        }
    }

    /// Hosted ödeme sayfası kapandığında ödeme durumunu yoklar.
    func resolveHostedCheckout(paymentId: String) async {
        let hold = checkoutHold
        checkoutHold = nil
        outcome = nil
        isCheckingPayment = true
        let status = await pollPayment(paymentId: paymentId)
        isCheckingPayment = false
        guard let slot = selectedSlot else { return }
        if let status, status.isSuccess {
            var saved = makeSavedReservation(slot: slot, created: nil)
            saved.status = "CONFIRMED"
            saved.remoteUUID = status.reservationUuid
            confirm(saved, message: completionMessage)
        } else if let status, status.isFailure {
            paymentNotice = status.errorMessage?.nilIfBlank ?? "Ödeme tamamlanmadı. Hazır olduğunda tekrar deneyebilirsin."
            // Ödeme kesin olarak başarısız: bekletme beklemeden bırakılabilir.
            if let hold { releaseHold(hold, after: .zero) }
        } else {
            paymentNotice = "Ödeme sonucu henüz gelmedi. Tamamlandıysa onay e-postası birkaç dakika içinde ulaşır."
        }
    }

    private var completionMessage: String {
        selectedSlot?.slot.isPreauth == true ? "Kart provizyonun alındı; tutar kartından çekilmedi." : "Ödemen alındı."
    }

    /// Bekletme ödeme tamamlanmadan bırakıldığında masa 5 dakika boyunca başkalarına kapalı kalır.
    /// 3D Secure dönüşü sunucuda hâlâ işleniyor olabileceği için önce kısa bir süre beklenir ve
    /// rezervasyon yeniden aranır; sunucu da rezervasyona dönüşmüş bekletmeyi iptal etmez.
    /// Hata sessizce yutulur: bekletmenin süresi zaten kendiliğinden dolar.
    private func releaseHold(_ hold: PendingHold, after grace: Duration? = nil) {
        let api = self.api
        let delay = grace ?? holdReleaseGrace
        Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            if grace == nil {
                switch await Self.lookUp(hold, api: api) {
                case .completed(let reservation):
                    self?.applyLateCompletion(reservation)
                    return
                case .unknown:
                    return
                case .notCompleted:
                    break
                }
            }
            guard let result = try? await api.cancelReservationHold(id: hold.id, uuid: hold.uuid) else { return }
            if result.wasConverted, case .completed(let reservation) = await Self.lookUp(hold, api: api) {
                self?.applyLateCompletion(reservation)
            }
        }
    }

    private func applyLateCompletion(_ reservation: CustomerReservation) {
        // Kullanıcı bu arada yeni bir deneme başlattıysa ekranı değiştirme; kayıt listede zaten görünür.
        guard step != .done, pendingHold == nil, !isSubmitting else { return }
        paymentNotice = nil
        confirm(makeSavedReservation(remote: reservation), message: completionMessage)
    }

    private static func lookUp(_ hold: PendingHold, api: PublicAPI) async -> HoldLookup {
        guard let reservations = try? await api.customerReservations() else { return .unknown }
        if let match = reservations.first(where: hold.matches) { return .completed(match) }
        return .notCompleted
    }

    // MARK: Kayıt

    /// Onaylanan rezervasyonun yerel kaydı.
    func makeSavedReservation(slot: SlotOption, created: ReservationCreated?) -> SavedReservation {
        makeSaved(
            day: date,
            guests: guestCount,
            remoteId: created?.reservationId,
            remoteUUID: created?.reservationUuid,
            startTime: created?.startTime ?? slot.slot.startTime,
            endTime: created?.endTime ?? slot.slot.endTime,
            status: created?.reservationStatus ?? (slot.slot.isRequestOnly ? "PENDING" : "CONFIRMED"),
            managementURL: created?.managementUrl
        )
    }

    /// Web'de ödemesi tamamlanan ve hesaba bağlanan rezervasyonun yerel kaydı.
    private func makeSavedReservation(remote: CustomerReservation) -> SavedReservation {
        // Kullanıcı ekranda tarih veya kişi sayısını değiştirmiş olabilir; sunucu kaydı esastır.
        var saved = makeSaved(
            day: remote.reservationDate.flatMap(DateFormat.parseAPIDay) ?? date,
            guests: remote.guestCount,
            remoteId: remote.id,
            remoteUUID: remote.uuid,
            startTime: remote.startTime ?? selectedSlot?.slot.startTime ?? "00:00",
            endTime: remote.endTime ?? selectedSlot?.slot.endTime,
            status: remote.status ?? "CONFIRMED",
            managementURL: remote.managementUrl
        )
        saved.checkedIn = remote.checkedIn
        return saved
    }

    private func makeSaved(day: Date, guests: Int, remoteId: Int?, remoteUUID: String?, startTime: String, endTime: String?, status: String, managementURL: String?) -> SavedReservation {
        SavedReservation(
            id: UUID(),
            kind: .restaurant,
            remoteId: remoteId,
            remoteUUID: remoteUUID,
            title: context.name,
            subtitle: context.subtitle,
            image: context.image,
            startDate: SavedReservation.combine(day: day, time: startTime),
            endDate: endTime.map { SavedReservation.combine(day: day, time: $0) },
            timeText: startTime.shortTime,
            guestCount: guests,
            status: status,
            customerName: name.trimmingCharacters(in: .whitespaces),
            note: note.nilIfBlank,
            venueId: context.venueId,
            listingSlug: context.listingSlug,
            eventId: nil,
            address: context.address,
            phone: context.phone,
            latitude: context.latitude,
            longitude: context.longitude,
            createdAt: .now,
            managementURL: managementURL
        )
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

extension APIError {
    /// `POST /reservations` kart bilgisi gerektiğinde kodsuz `400 {requiresPayment: true}` döner.
    /// Bekletme ve kart tipi hataları da bu bayrağı taşır; onlar ödeme adımının kendisine aittir.
    var requestsCardPayment: Bool {
        statusCode == 400 && requiresPayment == true && !Self.paymentStepCodes.contains(code ?? "")
    }

    private static let paymentStepCodes: Set<String> = ["holdInvalid", "holdExpired", "PREAUTH_CREDIT_CARD_REQUIRED", "PAYMENT_INIT_FAILED"]
}

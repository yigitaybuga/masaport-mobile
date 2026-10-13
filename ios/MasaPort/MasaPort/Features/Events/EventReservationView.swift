import SwiftUI

@MainActor
@Observable
final class EventReservationViewModel {
    enum Outcome: Equatable {
        case confirmed(SavedReservation)
        case hostedCheckout(url: URL, paymentId: String)
        /// Kart bilgisi isteyen ödeme: bilet güvenli web sayfasından alınır.
        case handedOffToWeb(URL)
    }

    let event: EventDetail
    let instance: EventInstance

    var guestCount = 1
    private(set) var selectedTicketID: String?
    var name: String
    var phone: String
    var email: String
    var note = ""
    var participants: [String] = []
    var rememberMe: Bool
    var consent = false

    private(set) var isSubmitting = false
    private(set) var submitError: String?
    private(set) var outcome: Outcome?

    private let api: PublicAPI
    private let preferences: PreferencesStore
    private let canPayInApp: Bool

    init(event: EventDetail, instance: EventInstance, preferences: PreferencesStore, account: CustomerAccount? = nil, canPayInApp: Bool = false, api: PublicAPI = .shared) {
        self.event = event
        self.instance = instance
        self.preferences = preferences
        self.canPayInApp = canPayInApp
        self.api = api
        name = account?.name ?? preferences.guest.name
        phone = account?.phone ?? preferences.guest.phone
        email = account?.email ?? preferences.guest.email
        rememberMe = preferences.rememberGuest
        // Tek seçilebilir bilet varsa hazır seçili gelir.
        let available = ticketChoices.filter { !$0.isSoldOut }
        if available.count == 1 { selectedTicketID = available[0].id }
    }

    /// Seans için satışa açık biletler (kapalı seçenekler hiç gösterilmez).
    var ticketChoices: [EventTicketChoice] { event.ticketChoices(for: instance) }
    var selectedTicket: EventTicketChoice? { ticketChoices.first { $0.id == selectedTicketID } }

    func selectTicket(_ choice: EventTicketChoice) {
        guard !choice.isSoldOut else { return }
        selectedTicketID = choice.id
        guestCount = min(guestCount, maxGuests)
        syncParticipants()
    }

    var maxGuests: Int {
        var limit = 10
        if let spots = instance.availableSpots, instance.maxCapacity != nil { limit = min(limit, spots) }
        if let available = selectedTicket?.available { limit = min(limit, available) }
        return max(1, limit)
    }

    /// Kişi başı fiyat: bilet seçenekli etkinlikte seçilen biletin fiyatı.
    var unitPrice: Double {
        guard event.collectsPayment else { return 0 }
        if event.requiresTicketOption { return selectedTicket?.unitPrice ?? 0 }
        return event.price ?? 0
    }

    /// Sunucuyla aynı yuvarlama: kuruş cinsinden birim fiyat × kişi.
    var totalAmount: Double { (unitPrice * 100).rounded() * Double(guestCount) / 100 }
    var requiresPayment: Bool { event.collectsPayment && totalAmount > 0 }
    /// Kart bilgisi isteyen sağlayıcıda ücretli bilet uygulama içinde alınamaz.
    var needsWebPayment: Bool { requiresPayment && !canPayInApp }

    var isTicketChoiceValid: Bool {
        guard event.requiresTicketOption else { return true }
        guard let selectedTicket, !selectedTicket.isSoldOut else { return false }
        return selectedTicket.available.map { $0 >= guestCount } ?? true
    }
    var isNameValid: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 }
    var isEmailValid: Bool { email.contains("@") && email.contains(".") }
    var normalizedPhone: String? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return trimmed.hasPrefix("+") ? "+\(digits)" : digits
    }
    var canSubmit: Bool {
        guard isTicketChoiceValid, !isSubmitting else { return false }
        // Web'e devredilen ödemede iletişim bilgileri web formunda alınır.
        return needsWebPayment || (isNameValid && isEmailValid && consent)
    }

    func syncParticipants() {
        let needed = max(0, guestCount - 1)
        if participants.count < needed { participants.append(contentsOf: Array(repeating: "", count: needed - participants.count)) }
        if participants.count > needed { participants = Array(participants.prefix(needed)) }
    }

    func submit() async {
        guard canSubmit else { return }
        if needsWebPayment {
            outcome = .handedOffToWeb(AppConfiguration.webEventTicketURL(eventID: event.id))
            return
        }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        if rememberMe {
            preferences.rememberGuest = true
            preferences.guest = .init(name: name.trimmingCharacters(in: .whitespaces), phone: normalizedPhone ?? "", email: email.trimmingCharacters(in: .whitespaces))
        }

        let names = [name.trimmingCharacters(in: .whitespaces)] + participants.compactMap(\.nilIfBlank)
        let request = EventReservationRequest(
            contactName: name.trimmingCharacters(in: .whitespaces),
            contactEmail: email.trimmingCharacters(in: .whitespaces),
            contactPhone: normalizedPhone,
            guestCount: guestCount,
            participants: names.map { .init(name: $0) },
            notes: note.nilIfBlank,
            couponCode: nil,
            ticketOptionId: event.requiresTicketOption ? selectedTicketID : nil
        )
        do {
            let created = try await api.createEventReservation(eventId: event.id, instanceId: instance.id, request: request)
            if created.needsPayment {
                if let url = created.checkoutUrl.flatMap(URL.init(string:)), let paymentId = created.paymentId {
                    outcome = .hostedCheckout(url: url, paymentId: paymentId)
                } else {
                    submitError = "Bu etkinlik için ödeme uygulama içinde tamamlanamıyor. Web üzerinden bilet alabilirsin."
                }
                return
            }
            outcome = .confirmed(makeSaved(created: created))
        } catch let error as APIError {
            submitError = error.detail ?? error.message
        } catch {
            submitError = error.localizedDescription
        }
    }

    /// Web ödeme sayfası kapandı; kullanıcı başka bir bilet seçip yeniden deneyebilsin.
    func webHandoffDidClose() {
        if case .handedOffToWeb = outcome { outcome = nil }
    }

    func makeSaved(created: EventReservationCreated?) -> SavedReservation {
        let start = instance.startDate ?? .now
        return SavedReservation(
            id: UUID(),
            kind: .event,
            remoteId: created?.id,
            remoteUUID: created?.uuid,
            title: event.title,
            subtitle: [event.venue?.name ?? event.location?.name, event.location?.district?.name ?? event.location?.city?.name].compactMap { $0?.nilIfBlank }.joined(separator: " · "),
            image: event.imageUrl,
            startDate: start,
            endDate: instance.endDate,
            timeText: DateFormat.time.string(from: start),
            guestCount: guestCount,
            status: "CONFIRMED",
            customerName: name.trimmingCharacters(in: .whitespaces),
            note: note.nilIfBlank,
            venueId: event.venue?.id,
            listingSlug: nil,
            eventId: event.id,
            address: event.location?.address ?? event.venue?.address,
            phone: event.venue?.phone,
            latitude: event.location?.latitude?.value,
            longitude: event.location?.longitude?.value,
            createdAt: .now
        )
    }

    func pollPayment(paymentId: String) async -> PaymentStatus? {
        for _ in 0..<20 {
            if let status = try? await api.paymentStatus(paymentId: paymentId), status.isFinal { return status }
            try? await Task.sleep(for: .seconds(2))
        }
        return nil
    }
}

struct EventReservationView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: EventReservationViewModel?

    let event: EventDetail
    let instance: EventInstance

    var body: some View {
        Group {
            if let viewModel {
                EventReservationContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = EventReservationViewModel(event: event, instance: instance, preferences: model.preferences, account: model.customerSession.account, canPayInApp: model.canPayInApp)
            }
        }
    }
}

private struct EventReservationContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: EventReservationViewModel
    @State private var confirmed: SavedReservation?
    @State private var safari: SafariDestination?
    @State private var pendingPaymentId: String?

    var body: some View {
        NavigationStack {
            Group {
                if let confirmed {
                    ReservationConfirmationView(reservation: confirmed, message: nil) { dismiss() }
                } else {
                    form
                }
            }
            .background(MP.background)
            .navigationTitle(confirmed == nil ? "Yer ayırt" : "Kaydın alındı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(confirmed == nil ? "Vazgeç" : "Kapat") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .onChange(of: viewModel.outcome) { _, outcome in
            switch outcome {
            case .confirmed(let saved):
                model.reservations.add(saved)
                withAnimation { confirmed = saved }
            case .hostedCheckout(let url, let paymentId):
                pendingPaymentId = paymentId
                safari = SafariDestination(url: url)
            case .handedOffToWeb(let url):
                safari = SafariDestination(url: url)
            case nil:
                break
            }
        }
        .fullScreenCover(item: $safari) { destination in
            SafariView(url: destination.url) {
                safari = nil
                guard let paymentId = pendingPaymentId else {
                    viewModel.webHandoffDidClose()
                    return
                }
                pendingPaymentId = nil
                Task {
                    if let status = await viewModel.pollPayment(paymentId: paymentId), status.isSuccess {
                        let saved = viewModel.makeSaved(created: nil)
                        model.reservations.add(saved)
                        withAnimation { confirmed = saved }
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    MPRemoteImage(url: .media(viewModel.event.imageUrl), placeholderSymbol: "ticket", role: .thumbnail)
                        .frame(width: 64, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.event.title).font(.headline).lineLimit(2)
                        Text(Format.eventDate(viewModel.instance.startDate))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MP.warm)
                        if let badge = viewModel.instance.availabilityBadge {
                            MPPill(text: badge.text, tone: badge.tone)
                        }
                    }
                }

                if viewModel.event.requiresTicketOption {
                    ticketSection
                }

                MPStepper(title: "Kişi sayısı", value: $viewModel.guestCount, range: 1...viewModel.maxGuests)
                    .padding(16)
                    .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                    .onChange(of: viewModel.guestCount) { _, _ in viewModel.syncParticipants() }

                if viewModel.needsWebPayment {
                    MPNotice(message: "Bu bilet ücretli; ödeme güvenli web sayfasında tamamlanır. Açılan sayfada seansı ve bileti yeniden seçmen gerekebilir.", tone: .brand)
                } else {
                    contactForm
                }

                if let error = viewModel.submitError {
                    MPNotice(message: error)
                }
            }
            .padding(MP.gutter)
            .padding(.bottom, 90)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom) {
            Button {
                Task { await viewModel.submit() }
            } label: {
                HStack {
                    if viewModel.isSubmitting { ProgressView().tint(MP.onBrand) }
                    Text(submitTitle).font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
            .disabled(!viewModel.canSubmit)
            .padding(.horizontal, MP.gutter)
            .padding(.vertical, 10)
        }
    }

    // MARK: Bilet seçimi

    private var ticketSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bilet").font(.headline)
            if viewModel.ticketChoices.isEmpty {
                MPNotice(message: "Bu seans için satışta bilet bulunmuyor.", tone: .attention)
            } else if viewModel.selectedTicket == nil {
                Text("Devam etmek için bir bilet seç.")
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            ForEach(viewModel.ticketChoices) { choice in
                TicketOptionRow(choice: choice, isSelected: viewModel.selectedTicketID == choice.id) {
                    withAnimation(.snappy) { viewModel.selectTicket(choice) }
                }
            }
            if let selected = viewModel.selectedTicket, let available = selected.available, available < viewModel.guestCount {
                MPNotice(message: "Bu bilet için en fazla \(available) kişilik yer kaldı.", tone: .attention)
            }
        }
    }

    // MARK: İletişim

    private var contactForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 14) {
                MPLabeledField(label: "Ad Soyad") {
                    TextField("Adın ve soyadın", text: $viewModel.name).textContentType(.name)
                }
                MPLabeledField(label: "E-posta", hint: "QR kodun ve biletin e-postana gelir.") {
                    TextField("E-posta adresin", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                MPLabeledField(label: "Telefon (isteğe bağlı)") {
                    TextField("+90 5xx xxx xx xx", text: $viewModel.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                ForEach(viewModel.participants.indices, id: \.self) { index in
                    MPLabeledField(label: "\(index + 2). katılımcı (isteğe bağlı)") {
                        TextField("Ad Soyad", text: $viewModel.participants[index])
                    }
                }
                MPLabeledField(label: "Not (isteğe bağlı)") {
                    TextField("Ek bilgi", text: $viewModel.note, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.vertical, 10)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $viewModel.rememberMe) { Text("Bilgilerimi bu cihazda hatırla").font(.subheadline) }
                Toggle(isOn: $viewModel.consent) { Text("Kişisel verilerimin etkinlik kaydı için işlenmesini kabul ediyorum").font(.subheadline) }
            }
            .padding(16)
            .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
            .tint(MP.brand)
        }
    }

    private var submitTitle: String {
        if viewModel.isSubmitting { return "Gönderiliyor" }
        let total = viewModel.requiresPayment ? Format.price(viewModel.totalAmount) : nil
        if viewModel.needsWebPayment { return total.map { "Güvenli ödemeye geç · \($0)" } ?? "Güvenli ödemeye geç" }
        if let total { return "Ödemeye geç · \(total)" }
        return "Kaydı tamamla"
    }
}

/// Bilet seçeneği satırı: bilet türü, kategori/bölüm, fiyat ve kalan kontenjan.
struct TicketOptionRow: View {
    let choice: EventTicketChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? MP.brand : Color(.tertiaryLabel))
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.label))
                    if let detail = choice.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    if choice.isSoldOut {
                        MPPill(text: "Tükendi", tone: .critical)
                    } else if choice.isLowStock, let available = choice.available {
                        MPPill(text: "Son \(available) bilet", tone: .warm)
                    }
                }
                Spacer(minLength: 8)
                Text(Format.price(choice.unitPrice) ?? "Ücretsiz")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(choice.isFree ? MP.positive : Color(.label))
            }
            .padding(14)
            .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MP.radius, style: .continuous)
                    .strokeBorder(isSelected ? MP.brand : .clear, lineWidth: 1.5)
            }
            .opacity(choice.isSoldOut ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(choice.isSoldOut)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

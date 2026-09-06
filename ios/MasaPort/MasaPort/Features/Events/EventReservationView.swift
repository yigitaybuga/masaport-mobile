import SwiftUI

@MainActor
@Observable
final class EventReservationViewModel {
    enum Outcome: Equatable {
        case confirmed(SavedReservation)
        case hostedCheckout(url: URL, paymentId: String)
    }

    let event: EventDetail
    let instance: EventInstance

    var guestCount = 1
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

    init(event: EventDetail, instance: EventInstance, preferences: PreferencesStore, account: CustomerAccount? = nil, api: PublicAPI = .shared) {
        self.event = event
        self.instance = instance
        self.preferences = preferences
        self.api = api
        name = account?.name ?? preferences.guest.name
        phone = account?.phone ?? preferences.guest.phone
        email = account?.email ?? preferences.guest.email
        rememberMe = preferences.rememberGuest
    }

    var maxGuests: Int {
        if let spots = instance.availableSpots, instance.maxCapacity != nil { return max(1, min(spots, 10)) }
        return 10
    }

    var totalAmount: Double { (event.price ?? 0) * Double(guestCount) }
    var isNameValid: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 }
    var isEmailValid: Bool { email.contains("@") && email.contains(".") }
    var normalizedPhone: String? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return trimmed.hasPrefix("+") ? "+\(digits)" : digits
    }
    var canSubmit: Bool { isNameValid && isEmailValid && consent && !isSubmitting }

    func syncParticipants() {
        let needed = max(0, guestCount - 1)
        if participants.count < needed { participants.append(contentsOf: Array(repeating: "", count: needed - participants.count)) }
        if participants.count > needed { participants = Array(participants.prefix(needed)) }
    }

    func submit() async {
        guard canSubmit else { return }
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
            couponCode: nil
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
                viewModel = EventReservationViewModel(event: event, instance: instance, preferences: model.preferences, account: model.customerSession.account)
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
            case nil:
                break
            }
        }
        .fullScreenCover(item: $safari) { destination in
            SafariView(url: destination.url) {
                safari = nil
                guard let paymentId = pendingPaymentId else { return }
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
                    MPRemoteImage(url: .media(viewModel.event.imageUrl), placeholderSymbol: "ticket")
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

                MPStepper(title: "Kişi sayısı", value: $viewModel.guestCount, range: 1...viewModel.maxGuests)
                    .padding(16)
                    .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                    .onChange(of: viewModel.guestCount) { _, _ in viewModel.syncParticipants() }

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

    private var submitTitle: String {
        if viewModel.isSubmitting { return "Gönderiliyor" }
        if let total = Format.price(viewModel.totalAmount) { return "Ödemeye geç · \(total)" }
        return "Kaydı tamamla"
    }
}

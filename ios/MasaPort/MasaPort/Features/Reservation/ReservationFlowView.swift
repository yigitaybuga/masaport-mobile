import SwiftUI

struct ReservationFlowView: View {
    @Environment(AppModel.self) private var model
    @State private var viewModel: ReservationViewModel?

    let context: ReservationContext
    let initialDate: Date
    let initialGuests: Int
    let initialTime: String?
    var preloadedAvailability: VenueAvailability? = nil

    var body: some View {
        Group {
            if let viewModel {
                ReservationFlowContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = ReservationViewModel(
                context: context,
                initialDate: initialDate,
                initialGuests: initialGuests,
                initialTime: initialTime,
                preloadedAvailability: preloadedAvailability,
                preferences: model.preferences,
                canPayInApp: model.canPayInApp,
                account: model.customerSession.account
            )
        }
    }
}

private struct ReservationFlowContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReservationViewModel
    @State private var safari: SafariDestination?
    @State private var pendingPaymentId: String?
    @State private var paymentMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .slot: slotStep
                case .details: detailsStep
                case .done: doneStep
                }
            }
            .background(MP.background)
            .navigationTitle(viewModel.step == .done ? "Rezervasyon alındı" : viewModel.context.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.step == .details {
                        Button("Geri") { withAnimation { viewModel.step = .slot } }
                    } else {
                        Button(viewModel.step == .done ? "Kapat" : "Vazgeç") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .task { await viewModel.loadAvailability() }
        .onChange(of: viewModel.outcome) { _, outcome in
            guard let outcome else { return }
            switch outcome {
            case .confirmed(let saved, _):
                model.reservations.add(saved)
            case .handedOffToWeb(let url):
                safari = SafariDestination(url: url)
            case .hostedCheckout(let url, let paymentId):
                pendingPaymentId = paymentId
                safari = SafariDestination(url: url)
            }
        }
        .fullScreenCover(item: $safari) { destination in
            SafariView(url: destination.url) {
                safari = nil
                handleSafariDismiss()
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Adım 1 – Saat

    private var slotStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                venueHeader
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tarih").font(.headline)
                    DayStrip(selected: $viewModel.date, bleed: MP.gutter)
                }
                MPStepper(title: "Kişi sayısı", value: $viewModel.guestCount)
                    .padding(16)
                    .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Saat").font(.headline)
                    if viewModel.isLoadingAvailability, viewModel.availability == nil {
                        MPLoadingRow(title: "Müsaitlik kontrol ediliyor")
                    } else if let error = viewModel.availabilityError {
                        MPNotice(message: error, actionTitle: "Tekrar dene") {
                            Task { await viewModel.loadAvailability(force: true) }
                        }
                    } else if viewModel.slotOptions.isEmpty {
                        Text("Seçtiğin gün için tanımlı saat yok.")
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryLabel))
                    } else {
                        SlotGrid(options: viewModel.slotOptions, selected: viewModel.selectedSlot?.id) { option in
                            withAnimation(.snappy) { viewModel.selectedSlot = option }
                        }
                        .opacity(viewModel.isLoadingAvailability ? 0.5 : 1)
                    }
                    if let slot = viewModel.selectedSlot?.slot {
                        slotNotes(slot)
                    }
                }
            }
            .padding(MP.gutter)
            .padding(.bottom, 90)
        }
        .onChange(of: viewModel.date) { _, _ in Task { await viewModel.loadAvailability() } }
        .onChange(of: viewModel.guestCount) { _, _ in Task { await viewModel.loadAvailability() } }
        .safeAreaBar(edge: .bottom) {
            Button {
                viewModel.continueToDetails()
            } label: {
                Text("Devam et")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
            .disabled(viewModel.selectedSlot == nil)
            .padding(.horizontal, MP.gutter)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func slotNotes(_ slot: PublicSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if slot.isRequestOnly {
                MPNotice(message: slot.bookingMessage?.nilIfBlank ?? "Bu saat için rezervasyon mekan onayından sonra kesinleşir.", tone: .attention)
            }
            if slot.prepaymentRequired == true {
                MPNotice(message: slot.prepaymentSummary?.nilIfBlank ?? "Bu saat için ön ödeme alınır. Ödeme güvenli web sayfasında tamamlanır.", tone: .brand)
            }
            if slot.minimumSpendRequired == true, let summary = slot.minimumSpendSummary?.nilIfBlank {
                MPNotice(message: summary, tone: .neutral)
            }
        }
    }

    // MARK: Adım 2 – Bilgiler

    private var detailsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                VStack(spacing: 14) {
                    MPLabeledField(label: "Ad Soyad") {
                        TextField("Adın ve soyadın", text: $viewModel.name)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                    }
                    MPLabeledField(label: "Telefon", hint: "Onay mesajı bu numaraya gönderilir.") {
                        TextField("+90 5xx xxx xx xx", text: $viewModel.phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                    }
                    MPLabeledField(label: "E-posta", hint: "Rezervasyon QR kodun e-postana gelir.") {
                        TextField("E-posta adresin", text: $viewModel.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    MPLabeledField(label: "Not (isteğe bağlı)") {
                        TextField("Pencere kenarı, doğum günü, alerji…", text: $viewModel.note, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(.vertical, 10)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $viewModel.rememberMe) {
                        Text("Bilgilerimi bu cihazda hatırla").font(.subheadline)
                    }
                    Toggle(isOn: $viewModel.kvkkAccepted) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kişisel verilerimin işlenmesini kabul ediyorum").font(.subheadline)
                            if let kvkk = viewModel.kvkkText {
                                NavigationLink {
                                    ScrollView {
                                        Text(kvkk.content ?? "")
                                            .font(.footnote)
                                            .padding()
                                    }
                                    .navigationTitle(kvkk.title ?? "Aydınlatma metni")
                                    .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    Text(kvkk.title ?? "Aydınlatma metnini oku")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
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
                    Text(
                        viewModel.isSubmitting
                            ? "Hazırlanıyor"
                            : viewModel.requiresWebHandoff ? "Ödemeye geç" : "Rezervasyonu tamamla"
                    )
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(MP.action)
            .controlSize(.large)
            .disabled(!viewModel.canSubmit)
            .padding(.horizontal, MP.gutter)
            .padding(.vertical, 10)
        }
    }

    // MARK: Adım 3 – Onay

    @ViewBuilder
    private var doneStep: some View {
        if case let .confirmed(saved, message) = viewModel.outcome {
            ReservationConfirmationView(reservation: saved, message: message ?? paymentMessage) { dismiss() }
        } else {
            ProgressView()
        }
    }

    // MARK: Parçalar

    private var venueHeader: some View {
        HStack(spacing: 12) {
            MPRemoteImage(url: .media(viewModel.context.image), role: .thumbnail)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.context.name).font(.headline)
                Text(viewModel.context.subtitle).font(.subheadline).foregroundStyle(Color(.secondaryLabel)).lineLimit(2)
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(MP.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.context.name).font(.headline)
                Text(viewModel.timeSummary).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
            Button("Değiştir") { withAnimation { viewModel.step = .slot } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
    }

    private func handleSafariDismiss() {
        guard let paymentId = pendingPaymentId, let slot = viewModel.selectedSlot else {
            // Web'e devredilen akış: kullanıcı web'de tamamladıysa kayıt e-postayla gelir.
            if case .handedOffToWeb = viewModel.outcome { dismiss() }
            return
        }
        pendingPaymentId = nil
        Task {
            let status = await viewModel.pollPayment(paymentId: paymentId)
            if let status, status.isSuccess {
                var saved = viewModel.makeSavedReservation(slot: slot, created: nil)
                saved.status = "CONFIRMED"
                saved.remoteUUID = status.reservationUuid
                model.reservations.add(saved)
                paymentMessage = "Ödemen alındı."
                viewModel.step = .done
            } else {
                paymentMessage = nil
            }
        }
    }
}

struct ReservationConfirmationView: View {
    let reservation: SavedReservation
    var message: String?
    let onClose: () -> Void

    @State private var calendarOutcome: CalendarExport.Outcome?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(MP.positive.opacity(0.14)).frame(width: 96, height: 96)
                    Image(systemName: reservation.isPending ? "clock.badge.checkmark.fill" : "checkmark.seal.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(reservation.isPending ? MP.attention : MP.positive)
                        .symbolEffect(.bounce, options: .nonRepeating)
                }
                .padding(.top, 12)
                VStack(spacing: 6) {
                    Text(headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text(subheadline)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                if let message {
                    MPNotice(message: message, tone: .brand)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ConfirmationRow(icon: reservation.kind == .event ? "ticket" : "fork.knife", title: reservation.title, detail: reservation.subtitle)
                    Divider()
                    ConfirmationRow(icon: "calendar", title: DateFormat.longDay.string(from: reservation.startDate), detail: reservation.timeText)
                    Divider()
                    ConfirmationRow(icon: "person.2", title: Format.guests(reservation.guestCount), detail: reservation.customerName)
                }
                .mpCard()
                HStack(spacing: 10) {
                    Button {
                        Task { calendarOutcome = await CalendarExport.add(reservation) }
                    } label: {
                        Label(calendarOutcome == .added ? "Takvime eklendi" : "Takvime ekle", systemImage: calendarOutcome == .added ? "checkmark" : "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(calendarOutcome == .added)
                    if let phone = reservation.phone, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                        Link(destination: url) {
                            Label("Mekanı ara", systemImage: "phone").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }
                if calendarOutcome == .denied {
                    Text("Takvim izni verilmedi. Ayarlar > MasaPort'tan açabilirsin.")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .padding(MP.gutter)
            .padding(.bottom, 90)
        }
        .safeAreaBar(edge: .bottom) {
            Button("Tamam", action: onClose)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .buttonStyle(.glassProminent).tint(MP.action)
                .controlSize(.large)
                .padding(.horizontal, MP.gutter)
                .padding(.vertical, 10)
        }
    }
}

extension ReservationConfirmationView {
    var headline: String {
        if reservation.kind == .event { return "Yerin ayrıldı" }
        return reservation.isPending ? "Talebin iletildi" : "Masan hazır olacak"
    }

    var subheadline: String {
        if reservation.kind == .event { return "QR kodun e-posta ile gönderildi; Rezervasyonlar sekmesinden de gösterebilirsin." }
        return reservation.isPending ? "Mekan onayladığında SMS ve e-posta ile haber vereceğiz." : "Onay ve QR kodun e-posta ile gönderildi."
    }
}

struct ConfirmationRow: View {
    let icon: String
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(MP.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail, !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                }
            }
            Spacer()
        }
    }
}

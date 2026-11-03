import SwiftUI

/// Kapı sırası: masa doluyken gelen misafirler. Web panelindeki "Kapı sırası" kartıyla aynı akış:
/// sıraya ekle → "Masa hazır" haberi → Oturt (walk-in kaydı sırayı kapatır) veya sıradan çıkar.
struct WalkInQueueView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = WalkInQueueViewModel()
    @StateObject private var liveUpdates = HostDeskLiveUpdates()
    @State private var showsAddSheet = false
    @State private var candidate: WalkInQueueActionCandidate?
    @State private var seatingEntry: WalkInQueueEntry?
    @State private var completionMessage: String?
    /// Sayfa kapanırken uyarı açılmaya çalışılmasın; mesaj sayfa kapandıktan sonra gösterilir.
    @State private var pendingCompletionMessage: String?
    @State private var feedbackTrigger = 0
    /// Bekleme süreleri dakikalık tazelemede yeniden hesaplanır.
    @State private var now = Date.now

    var body: some View {
        Group {
            if let venue = session.activeVenue {
                content(venueID: venue.id)
            } else {
                ContentUnavailableView("Mekan bulunamadı", systemImage: "building.2")
            }
        }
        .background(MP.background)
        .navigationTitle("Kapı sırası")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog(
            candidate?.title ?? "",
            isPresented: Binding(
                get: { candidate != nil },
                set: { if !$0 { candidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let candidate {
                Button(candidate.confirmationTitle, role: candidate.isDestructive ? .destructive : nil) {
                    perform(candidate)
                }
            }
        } message: {
            Text(candidate?.message ?? "")
        }
        .alert(
            "İşlem tamamlandı",
            isPresented: Binding(
                get: { completionMessage != nil },
                set: { if !$0 { completionMessage = nil } }
            )
        ) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(completionMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
        .sheet(isPresented: $showsAddSheet, onDismiss: showPendingCompletion) {
            if let venueID = session.activeVenue?.id {
                AddToWalkInQueueSheet(
                    partiesAhead: model.entries.count,
                    minutesPerParty: model.minutesPerParty,
                    suggestedQuote: model.suggestedQuoteMinutes
                ) { request in
                    if let message = await model.add(request, venueID: venueID) {
                        pendingCompletionMessage = message
                        feedbackTrigger += 1
                        return nil
                    }
                    return model.errorMessage ?? "Misafir sıraya eklenemedi."
                }
            }
        }
        .sheet(item: $seatingEntry) { entry in
            if let venueID = session.activeVenue?.id {
                WalkInView(venueID: venueID, prefill: entry.walkInPrefill) { _ in
                    feedbackTrigger += 1
                    Task { await model.load(venueID: venueID) }
                }
            }
        }
    }

    private func content(venueID: Int) -> some View {
        List {
            summary
                .mpPlainRow(vertical: 4)

            if let errorMessage = model.errorMessage {
                MPNotice(message: errorMessage, actionTitle: "Yenile") {
                    Task { await model.load(venueID: venueID) }
                }
                .mpPlainRow(vertical: 4)
            }

            if model.isLoading && model.entries.isEmpty {
                MPLoadingRow(title: "Kapı sırası yükleniyor")
                    .mpPlainRow()
            } else if model.entries.isEmpty {
                MPEmptyState(
                    systemImage: "door.left.hand.open",
                    title: "Sırada bekleyen yok",
                    message: "Masa doluyken gelen misafiri sıraya ekleyin. Masa hazır olunca WhatsApp ve e-postayla tek dokunuşla haber verirsiniz."
                )
                .mpCard(padding: 0)
                .mpPlainRow(vertical: 4)
            } else {
                Section {
                    ForEach(model.entries) { entry in
                        row(entry)
                    }
                } header: {
                    MPListSectionHeader(title: "Sırada", count: model.entries.count, tone: overdueCount > 0 ? .critical : .info)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                showsAddSheet = true
            } label: {
                Label("Sıraya ekle", systemImage: "plus")
            }
            .buttonStyle(MPPrimaryButtonStyle())
            .padding(.horizontal, MP.gutter)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .refreshable {
            now = .now
            await model.load(venueID: venueID)
        }
        .operationAutoRefresh(id: venueID, every: .seconds(60)) { trigger in
            now = .now
            // Arka planda soket sessizce ölmüş olabilir; ön plana dönüşte taze bağlantı kurulur.
            if trigger == .foreground {
                liveUpdates.connect(venueID: venueID)
            }
            await model.load(venueID: venueID, silent: trigger.isSilent)
        }
        .task(id: venueID) {
            liveUpdates.onChange = { event in
                // Sıra değişiklikleri "waitlist" kaynağıyla yayınlanır.
                guard event.venueID == venueID,
                      event.resources?.contains("waitlist") != false else { return }
                Task { await model.load(venueID: venueID) }
            }
            liveUpdates.onResync = {
                Task { await model.load(venueID: venueID) }
            }
            liveUpdates.connect(venueID: venueID)
        }
        .onDisappear { liveUpdates.disconnect() }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                MPMetric(value: model.entries.count, label: "Sırada", tone: model.entries.isEmpty ? .neutral : .info)
                summaryDivider
                MPMetric(value: notifiedCount, label: "Haber verildi", tone: notifiedCount > 0 ? .positive : .neutral)
                summaryDivider
                MPMetric(value: "~\(model.suggestedQuoteMinutes) dk", label: "Yeni gelen bekler")
            }
            HStack(spacing: 8) {
                Text("Grup başına ~\(model.minutesPerParty) dk · son oturtmalardan hesaplanır")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
                Spacer(minLength: 4)
                MPLiveIndicator(isConnected: liveUpdates.state == .connected)
            }
        }
        .mpCard(padding: 14)
    }

    private var summaryDivider: some View {
        Rectangle().fill(MP.hairline).frame(width: 1, height: 32).padding(.trailing, 12)
    }

    // MARK: Rows

    private func row(_ entry: WalkInQueueEntry) -> some View {
        let isOverdue = entry.isOverdue(at: now)
        let isBusy = model.actionEntryID == entry.id
        let blockTone: MPTone = isOverdue ? .critical : (entry.isNotified ? .positive : .neutral)

        return HStack(alignment: .center, spacing: 12) {
            MPTimeBlock(time: entry.position.map { "\($0)." } ?? "—", caption: "sıra", tone: blockTone)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.customerName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    MPTag(text: entry.partyText, systemImage: "person.2.fill")
                    if entry.isNotified {
                        MPTag(text: "Haber verildi", tone: .positive, systemImage: "bell.fill")
                    }
                }
                Label(entry.waitText(at: now), systemImage: "timer")
                    .font(.caption.weight(isOverdue ? .semibold : .regular))
                    .foregroundStyle(isOverdue ? MP.critical : Color(.secondaryLabel))
                    .lineLimit(1)
                if let note = entry.note {
                    Label(note, systemImage: "text.quote")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 8) {
                if !entry.isNotified {
                    Button {
                        candidate = WalkInQueueActionCandidate(entry: entry, kind: .notify)
                    } label: {
                        HStack(spacing: 5) {
                            if isBusy {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "bell.fill")
                            }
                            Text("Masa hazır")
                        }
                    }
                    .buttonStyle(MPCompactButtonStyle(tone: .brand))
                    .accessibilityLabel("\(entry.customerName) için masa hazır haberi gönder")
                }
                Button {
                    seatingEntry = entry
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill.checkmark")
                        Text("Oturt")
                    }
                }
                .buttonStyle(MPCompactButtonStyle(tone: .positive, filled: true))
                .accessibilityLabel("\(entry.customerName) için masa aç ve oturt")
            }
            .disabled(model.actionEntryID != nil)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowAccessibilityLabel(entry))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                seatingEntry = entry
            } label: {
                Label("Oturt", systemImage: "person.fill.checkmark")
            }
            .tint(MP.positive)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                candidate = WalkInQueueActionCandidate(entry: entry, kind: .remove)
            } label: {
                Label("Çıkar", systemImage: "xmark")
            }
            if let phoneURL = entry.phoneURL {
                Link(destination: phoneURL) {
                    Label("Ara", systemImage: "phone.fill")
                }
                .tint(MP.info)
            }
        }
        .contextMenu {
            if !entry.isNotified {
                Button("Masa hazır", systemImage: "bell") {
                    candidate = WalkInQueueActionCandidate(entry: entry, kind: .notify)
                }
            } else if entry.hasContactChannel {
                Button("Masa hazır mesajını tekrar gönder", systemImage: "bell.badge") {
                    candidate = WalkInQueueActionCandidate(entry: entry, kind: .notify)
                }
            }
            Button("Oturt (masa aç)", systemImage: "person.fill.checkmark") {
                seatingEntry = entry
            }
            Button("Masa açmadan oturtuldu", systemImage: "checkmark.circle") {
                candidate = WalkInQueueActionCandidate(entry: entry, kind: .seatWithoutTable)
            }
            if let phoneURL = entry.phoneURL, let phone = entry.customerPhone {
                Link(destination: phoneURL) {
                    Label("Ara \(phone)", systemImage: "phone")
                }
            }
            Section {
                Button("Beklemeden ayrıldı", systemImage: "figure.walk.departure") {
                    candidate = WalkInQueueActionCandidate(entry: entry, kind: .left)
                }
                Button("Sıradan çıkar", systemImage: "xmark.circle", role: .destructive) {
                    candidate = WalkInQueueActionCandidate(entry: entry, kind: .remove)
                }
            }
        }
    }

    private func rowAccessibilityLabel(_ entry: WalkInQueueEntry) -> String {
        var parts = [
            entry.position.map { "\($0). sıra" } ?? "Sırada",
            entry.customerName,
            entry.partyText,
            entry.waitText(at: now)
        ]
        if entry.isNotified { parts.append("haber verildi") }
        if let note = entry.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    // MARK: Actions

    private func perform(_ candidate: WalkInQueueActionCandidate) {
        self.candidate = nil
        guard let venueID = session.activeVenue?.id else { return }
        let entry = candidate.entry
        Task {
            let message: String?
            switch candidate.kind {
            case .notify:
                message = await model.notifyReady(entry, venueID: venueID)
            case .seatWithoutTable:
                message = await model.seatWithoutReservation(entry, venueID: venueID)
            case .left:
                message = await model.close(entry, status: "LEFT", venueID: venueID)
            case .remove:
                message = await model.close(entry, status: "CANCELLED", venueID: venueID)
            }
            if let message {
                completionMessage = message
                feedbackTrigger += 1
            }
        }
    }

    private func showPendingCompletion() {
        guard let message = pendingCompletionMessage else { return }
        pendingCompletionMessage = nil
        completionMessage = message
    }

    private var notifiedCount: Int { model.entries.count(where: \.isNotified) }
    private var overdueCount: Int { model.entries.count { $0.isOverdue(at: now) } }
}

/// Dış etkisi olan (mesaj gönderen) veya sırayı kapatan işlemler açık onay ister.
struct WalkInQueueActionCandidate {
    enum Kind: Equatable { case notify, seatWithoutTable, left, remove }

    let entry: WalkInQueueEntry
    let kind: Kind

    var title: String {
        switch kind {
        case .notify: entry.isNotified ? "Mesaj tekrar gönderilsin mi?" : "Masa hazır haberi verilsin mi?"
        case .seatWithoutTable: "Masa açmadan oturtulsun mu?"
        case .left: "Misafir beklemeden ayrıldı mı?"
        case .remove: "Sıradan çıkarılsın mı?"
        }
    }

    var confirmationTitle: String {
        switch kind {
        case .notify: entry.isNotified ? "Tekrar gönder" : "Haber ver"
        case .seatWithoutTable: "Oturtuldu olarak işaretle"
        case .left: "Ayrıldı olarak işaretle"
        case .remove: "Sıradan çıkar"
        }
    }

    var isDestructive: Bool { kind == .remove }

    var message: String {
        switch kind {
        case .notify:
            let channels = [entry.customerPhone != nil ? "WhatsApp" : nil, entry.customerEmail != nil ? "e-posta" : nil].compactMap { $0 }
            return channels.isEmpty
                ? "\(entry.customerName) için telefon veya e-posta yok. Kayıt haber verildi olarak işaretlenir; misafire sözlü haber verin."
                : "\(entry.customerName) için \u{201C}masanız hazır\u{201D} mesajı \(channels.joined(separator: " ve ")) ile gönderilecek."
        case .seatWithoutTable:
            return "\(entry.customerName) sıradan düşer, rezervasyon kaydı açılmaz. Telefonu olmayan misafir için kullanın."
        case .left:
            return "\(entry.customerName) sıradan düşer ve beklemeden ayrıldı olarak kaydedilir."
        case .remove:
            return "\(entry.customerName) kapı sırasından çıkarılacak."
        }
    }
}

// MARK: - Add sheet

/// Kapı sırasına misafir ekleme; söylenen bekleme süresi son oturtmalardan önerilir, personel değiştirebilir.
private struct AddToWalkInQueueSheet: View {
    let partiesAhead: Int
    let minutesPerParty: Int
    let suggestedQuote: Int
    /// Başarılıysa `nil`, değilse gösterilecek hata döner.
    let onSubmit: (WalkInQueueCreateRequest) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var customerName = ""
    @State private var customerPhone = ""
    @State private var customerEmail = ""
    @State private var partySize = 2
    @State private var quote: Int?
    @State private var note = ""
    @State private var sendLink = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case name, phone, email, note }
    private let quotePicks = [10, 15, 20, 30, 45]

    private var effectiveQuote: Int { quote ?? max(5, min(240, suggestedQuote)) }
    private var trimmedName: String { customerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPhone: String { customerPhone.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { customerEmail.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var phoneIsValid: Bool { trimmedPhone.isEmpty || trimmedPhone.filter(\.isNumber).count >= 10 }
    private var emailIsValid: Bool {
        guard !trimmedEmail.isEmpty else { return true }
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !trimmedEmail.contains(" ")
    }

    private var canSubmit: Bool {
        trimmedName.count >= 2 && phoneIsValid && emailIsValid && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MPNotice(
                        message: partiesAhead > 0
                            ? "Önünde \(partiesAhead) grup var. Tahmin grup başına ~\(minutesPerParty) dk."
                            : "Sırada bekleyen yok. Tahmin grup başına ~\(minutesPerParty) dk.",
                        tone: .info
                    )
                    guestSection
                    partySection
                    quoteSection
                    noteSection
                    if let errorMessage {
                        MPNotice(message: errorMessage)
                    }
                }
                .padding(.horizontal, MP.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MP.background)
            .navigationTitle("Kapı sırasına ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    focusedField = nil
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(MP.onBrand)
                        } else {
                            Image(systemName: "plus")
                        }
                        Text(isSubmitting ? "Ekleniyor…" : "Sıraya ekle")
                    }
                }
                .buttonStyle(MPPrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)
                .padding(.horizontal, MP.gutter)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var guestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Misafir", systemImage: "person.fill")
            VStack(spacing: 0) {
                formField(systemImage: "person", isFocused: focusedField == .name) {
                    TextField("Ad", text: $customerName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .phone }
                }
                Divider().padding(.leading, 54)
                formField(systemImage: "phone", isFocused: focusedField == .phone) {
                    TextField("Telefon (isteğe bağlı)", text: $customerPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                }
                Divider().padding(.leading, 54)
                formField(systemImage: "envelope", isFocused: focusedField == .email) {
                    TextField("E-posta (isteğe bağlı)", text: $customerEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                }
            }
            .mpCard(padding: 0)

            if !phoneIsValid {
                fieldHint("Telefon numarasını kontrol edin.", isError: true)
            } else if !emailIsValid {
                fieldHint("E-posta adresini kontrol edin.", isError: true)
            } else if !trimmedPhone.isEmpty {
                Toggle(isOn: $sendLink) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sıra bağlantısını gönder")
                            .font(.subheadline.weight(.medium))
                        Text("Misafir sırasını telefonundan takip eder.")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .tint(MP.positive)
                .mpCard(padding: 14)
            } else {
                fieldHint("Telefon veya e-posta verilirse masa hazır olunca tek dokunuşla haber verilir.")
            }
        }
    }

    private var partySection: some View {
        HStack {
            Label("Kişi sayısı", systemImage: "person.2.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.label))
            Spacer()
            stepper(value: partySize, label: "\(partySize)", accessibility: "Kişi sayısı \(partySize)") {
                if partySize > 1 { partySize -= 1 }
            } increment: {
                if partySize < 100 { partySize += 1 }
            }
        }
        .mpCard(padding: 14)
    }

    private var quoteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Söylenen bekleme", systemImage: "timer", detail: quote == nil ? "Önerilen" : nil)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(effectiveQuote) dakika")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    stepper(value: effectiveQuote, label: nil, accessibility: "Bekleme süresi \(effectiveQuote) dakika") {
                        quote = max(5, effectiveQuote - 5)
                    } increment: {
                        quote = min(240, effectiveQuote + 5)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(quotePicks, id: \.self) { minutes in
                            let isSelected = effectiveQuote == minutes
                            Button {
                                withAnimation(.snappy(duration: 0.18)) { quote = minutes }
                            } label: {
                                Text("\(minutes) dk")
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .padding(.horizontal, 13)
                                    .frame(height: 34)
                                    .foregroundStyle(isSelected ? MP.onBrand : Color(.label))
                                    .background(isSelected ? MP.brand : MP.fill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .mpCard(padding: 14)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Not", systemImage: "text.quote")
            TextField("Dış mekân istiyor, bebek arabası var…", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedField, equals: .note)
                .mpCard(padding: 14)
                .onChange(of: note) { _, newValue in
                    if newValue.count > 500 { note = String(newValue.prefix(500)) }
                }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = WalkInQueueCreateRequest(
            customerName: trimmedName,
            customerPhone: trimmedPhone.isEmpty ? nil : trimmedPhone,
            customerEmail: trimmedEmail.isEmpty ? nil : trimmedEmail,
            partySize: partySize,
            quotedWaitMinutes: effectiveQuote,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            sendLink: !trimmedPhone.isEmpty && sendLink
        )
        let failure = await onSubmit(request)
        isSubmitting = false
        if let failure {
            errorMessage = failure
        } else {
            dismiss()
        }
    }

    // MARK: Helpers

    private func fieldHint(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isError ? MP.critical : Color(.secondaryLabel))
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func formField<Content: View>(systemImage: String, isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            MPIconTile(systemImage: systemImage, tone: isFocused ? .brand : .neutral, size: 28)
            content().font(.body)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private func stepper(
        value: Int,
        label: String?,
        accessibility: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            stepperButton("minus", action: decrement)
            if let label {
                Text(label)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .frame(width: 44)
                    .contentTransition(.numericText())
            }
            stepperButton("plus", action: increment)
        }
        .background(MP.fill, in: Capsule())
        .animation(.snappy(duration: 0.18), value: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility)
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MP.brand)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Artır" : "Azalt")
    }
}

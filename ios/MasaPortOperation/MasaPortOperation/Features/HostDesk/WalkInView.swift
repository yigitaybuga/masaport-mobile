import SwiftUI

@MainActor
final class WalkInViewModel: ObservableObject {
    @Published var customerName = ""
    @Published var customerPhone = ""
    @Published var guestCount = 2
    @Published var startDate: Date
    @Published var durationMinutes = 90
    @Published var note = ""
    @Published var checkInNow = true
    @Published var selectedTableIDs: Set<Int> = []
    @Published private(set) var tableOptions: [AssignableTable] = []
    @Published private(set) var isLoadingTables = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var tableErrorMessage: String?
    @Published private(set) var result: WalkInResult?

    private let api: APIClient

    init(api: APIClient = .shared, prefill: WalkInPrefill? = nil) {
        self.api = api
        // Şu anki saati 5 dakikaya yuvarla.
        let now = Date()
        let seconds = Int(now.timeIntervalSince1970)
        startDate = Date(timeIntervalSince1970: TimeInterval(seconds - seconds % 300))
        if let prefill {
            customerName = prefill.customerName
            customerPhone = prefill.customerPhone
            guestCount = max(1, prefill.guestCount)
            note = prefill.note ?? ""
        }
    }

    var canSubmit: Bool {
        !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && customerPhone.filter(\.isNumber).count >= 10
            && guestCount > 0
            && !isSubmitting
    }

    /// Masa uygunluğunu yeniden yüklemeyi tetikleyen anahtar.
    var availabilityKey: String {
        "\(guestCount)-\(OperationDate.timeString(startDate))-\(durationMinutes)"
    }

    func loadTables(venueID: Int) async {
        isLoadingTables = true
        tableErrorMessage = nil
        defer { isLoadingTables = false }
        do {
            let payload: ReservationTableAvailability = try await api.get(
                "/reservations/\(venueID)/available-tables?reservation_date=\(OperationDate.today())&guest_count=\(guestCount)&start_time=\(OperationDate.timeString(startDate))&duration_minutes=\(durationMinutes)"
            )
            tableOptions = payload.tables
            let availableIDs = Set(payload.tables.filter(\.isAvailable).map(\.id))
            selectedTableIDs = selectedTableIDs.intersection(availableIDs)
        } catch let error as APIError {
            tableErrorMessage = error.detail ?? error.message
        } catch {
            guard !error.isCancellation else { return }
            tableErrorMessage = "Uygun masalar yüklenemedi."
        }
    }

    func submit(venueID: Int) async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created: WalkInResult = try await api.post(
                "/reservations/\(venueID)/walk-in",
                body: WalkInRequest(
                    customerName: customerName.trimmingCharacters(in: .whitespacesAndNewlines),
                    customerPhone: customerPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                    guestCount: guestCount,
                    startTime: OperationDate.timeString(startDate),
                    durationMinutes: durationMinutes,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    checkedIn: checkInNow,
                    tableIDs: selectedTableIDs.isEmpty ? nil : selectedTableIDs.sorted()
                )
            )
            result = created
            return true
        } catch let error as APIError {
            errorMessage = error.detail ?? error.message
            return false
        } catch {
            errorMessage = "Walk-in kaydı oluşturulamadı. Bağlantınızı kontrol edip tekrar deneyin."
            return false
        }
    }
}

/// Bekleme listesi gibi başka bir kaynaktan gelen ön doldurma.
struct WalkInPrefill {
    let customerName: String
    let customerPhone: String
    let guestCount: Int
    var note: String? = nil
    /// Başlıkta gösterilen kaynak açıklaması.
    var sourceTitle: String? = nil
}

/// Kapıdan gelen misafir için hızlı rezervasyon + check-in.
struct WalkInView: View {
    let venueID: Int
    var prefill: WalkInPrefill? = nil
    var onCreated: ((WalkInResult) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: WalkInViewModel

    init(venueID: Int, prefill: WalkInPrefill? = nil, onCreated: ((WalkInResult) -> Void)? = nil) {
        self.venueID = venueID
        self.prefill = prefill
        self.onCreated = onCreated
        _model = StateObject(wrappedValue: WalkInViewModel(prefill: prefill))
    }
    @FocusState private var focusedField: Field?
    @State private var feedbackTrigger = 0

    private enum Field { case name, phone, note }
    private let durations = [60, 90, 120, 150, 180]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let sourceTitle = prefill?.sourceTitle {
                        MPNotice(message: sourceTitle, tone: .info)
                    }
                    guestSection
                    reservationSection
                    tableSection
                    noteSection
                    if let errorMessage = model.errorMessage {
                        MPNotice(message: errorMessage)
                    }
                }
                .padding(.horizontal, MP.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MP.background)
            .navigationTitle("Walk-in misafir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                submitBar
            }
            .task(id: model.availabilityKey) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await model.loadTables(venueID: venueID)
            }
            .sensoryFeedback(.success, trigger: feedbackTrigger)
            .alert(
                "Misafir kaydedildi",
                isPresented: Binding(get: { model.result != nil }, set: { _ in })
            ) {
                Button("Tamam") {
                    if let result = model.result { onCreated?(result) }
                    dismiss()
                }
            } message: {
                if let result = model.result {
                    Text(successMessage(result))
                }
            }
        }
    }

    // MARK: Sections

    private var guestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Misafir", systemImage: "person.fill")
            VStack(spacing: 0) {
                formField(systemImage: "person", isFocused: focusedField == .name) {
                    TextField("Ad Soyad", text: $model.customerName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .phone }
                }
                Divider().padding(.leading, 54)
                formField(systemImage: "phone", isFocused: focusedField == .phone) {
                    TextField("Telefon", text: $model.customerPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                }
            }
            .mpCard(padding: 0)
        }
    }

    private var reservationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Rezervasyon", systemImage: "clock.fill")
            VStack(spacing: 16) {
                HStack {
                    Label("Kişi sayısı", systemImage: "person.2.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.label))
                    Spacer()
                    stepper
                }

                Divider()

                HStack {
                    Label("Başlangıç", systemImage: "clock")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.label))
                    Spacer()
                    DatePicker("Başlangıç", selection: $model.startDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.timeZone, TimeZone(identifier: "Europe/Istanbul")!)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Süre", systemImage: "hourglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.label))
                    MPSegmentBar(
                        segments: durations.map { MPSegment(id: $0, title: durationTitle($0)) },
                        selection: $model.durationMinutes
                    )
                }

                Divider()

                Toggle(isOn: $model.checkInNow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hemen check-in yap")
                            .font(.subheadline.weight(.medium))
                        Text(model.checkInNow ? "Misafir içeride sayılır, masa dolu görünür." : "Kayıt oluşturulur, geliş kaydı sonra yapılır.")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .tint(MP.positive)
            }
            .mpCard()
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepperButton("minus") { if model.guestCount > 1 { model.guestCount -= 1 } }
                .disabled(model.guestCount <= 1)
            Text(model.guestCount, format: .number)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .frame(width: 44)
                .contentTransition(.numericText())
            stepperButton("plus") { if model.guestCount < 40 { model.guestCount += 1 } }
                .disabled(model.guestCount >= 40)
        }
        .background(MP.fill, in: Capsule())
        .animation(.snappy(duration: 0.18), value: model.guestCount)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kişi sayısı \(model.guestCount)")
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
    }

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(
                title: "Masa",
                systemImage: "tablecells.fill",
                detail: model.selectedTableIDs.isEmpty ? "Otomatik" : "\(model.selectedTableIDs.count) masa seçili"
            )
            VStack(alignment: .leading, spacing: 12) {
                if model.isLoadingTables && model.tableOptions.isEmpty {
                    MPLoadingRow(title: "Uygun masalar kontrol ediliyor")
                } else if let tableErrorMessage = model.tableErrorMessage, model.tableOptions.isEmpty {
                    MPNotice(message: tableErrorMessage, tone: .attention, actionTitle: "Tekrar dene") {
                        Task { await model.loadTables(venueID: venueID) }
                    }
                } else if model.tableOptions.isEmpty {
                    Text("Masa seçilmezse sistem uygun masayı otomatik atar.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(model.tableOptions) { table in
                            tableChip(table)
                        }
                    }
                    .opacity(model.isLoadingTables ? 0.6 : 1)
                    Label(
                        model.selectedTableIDs.isEmpty
                            ? "Seçim yapmazsanız yıldızlı öneri otomatik atanır."
                            : "Seçili masalar rezervasyona bağlanacak.",
                        systemImage: "sparkles"
                    )
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .mpCard()
        }
    }

    private func tableChip(_ table: AssignableTable) -> some View {
        let isSelected = model.selectedTableIDs.contains(table.id)
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                if isSelected { model.selectedTableIDs.remove(table.id) } else { model.selectedTableIDs.insert(table.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(table.name)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(isSelected ? MP.onBrand : Color(.label))
                    if table.isRecommended {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? MP.onBrand : MP.attention)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(MP.onBrand)
                    }
                }
                Text("\(table.capacity) kişi\(table.zone.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(isSelected ? MP.onBrand.opacity(0.8) : Color(.secondaryLabel))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? MP.brand : MP.fill, in: RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : MP.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!table.isAvailable)
        .opacity(table.isAvailable ? 1 : 0.35)
        .accessibilityLabel("\(table.name), \(table.capacity) kişilik\(table.isRecommended ? ", önerilen" : "")\(table.isAvailable ? "" : ", dolu")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Not", systemImage: "text.quote")
            TextField("Alerji, özel istek, kutlama…", text: $model.note, axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedField, equals: .note)
                .mpCard(padding: 14)
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Button {
                focusedField = nil
                Task {
                    if await model.submit(venueID: venueID) { feedbackTrigger += 1 }
                }
            } label: {
                HStack(spacing: 8) {
                    if model.isSubmitting {
                        ProgressView().tint(MP.onBrand)
                    } else {
                        Image(systemName: model.checkInNow ? "person.fill.checkmark" : "plus")
                    }
                    Text(model.isSubmitting ? "Kaydediliyor…" : (model.checkInNow ? "Kaydet ve check-in yap" : "Rezervasyonu kaydet"))
                }
            }
            .buttonStyle(MPPrimaryButtonStyle())
            .disabled(!model.canSubmit)
            .opacity(model.canSubmit ? 1 : 0.5)
            .padding(.horizontal, MP.gutter)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    // MARK: Helpers

    private func formField<Content: View>(systemImage: String, isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            MPIconTile(systemImage: systemImage, tone: isFocused ? .brand : .neutral, size: 28)
            content().font(.body)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private func durationTitle(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60) sa" }
        return "\(minutes / 60),5 sa"
    }

    private func successMessage(_ result: WalkInResult) -> String {
        var parts = ["\(model.customerName.trimmingCharacters(in: .whitespacesAndNewlines)) için \(model.guestCount) kişilik kayıt oluşturuldu."]
        parts.append(result.tableSummary + ".")
        if result.checkedIn ?? model.checkInNow { parts.append("Misafir içeride görünüyor.") }
        return parts.joined(separator: " ")
    }
}

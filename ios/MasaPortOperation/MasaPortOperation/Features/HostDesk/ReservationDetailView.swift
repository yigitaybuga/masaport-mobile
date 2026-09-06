import SwiftUI

private struct TableAssignmentRequest: Encodable {
    let tableIDs: [Int]
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case tableIDs = "table_ids"
        case expectedUpdatedAt = "expected_updated_at"
    }
}

private struct ServiceStatusRequest: Encodable {
    let serviceStatus: String
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case serviceStatus = "service_status"
        case expectedUpdatedAt = "expected_updated_at"
    }
}

@MainActor
private final class ReservationDetailViewModel: ObservableObject {
    @Published private(set) var reservation: Reservation
    @Published private(set) var tableOptions: [AssignableTable] = []
    @Published var selectedTableIDs: Set<Int> = []
    @Published private(set) var isLoadingTables = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let venueID: Int
    private let api: APIClient

    init(reservation: Reservation, venueID: Int, api: APIClient = .shared) {
        self.reservation = reservation
        self.venueID = venueID
        self.api = api
        selectedTableIDs = Set(reservation.tables.map(\.id))
    }

    func loadTableOptions() async {
        isLoadingTables = true
        errorMessage = nil
        defer { isLoadingTables = false }

        do {
            let payload: ReservationTableAvailability = try await api.get(
                "/reservations/\(venueID)/\(reservation.id)/available-tables"
            )
            tableOptions = payload.tables
            selectedTableIDs = Set(payload.tables.filter(\.isCurrent).map(\.id))
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Uygun masalar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    func saveTables() async -> Bool {
        guard !selectedTableIDs.isEmpty else {
            errorMessage = "Rezervasyon için en az bir masa seçin."
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let result: ReservationTableAssignment = try await api.put(
                "/reservations/\(venueID)/\(reservation.id)/tables",
                body: TableAssignmentRequest(
                    tableIDs: selectedTableIDs.sorted(),
                    expectedUpdatedAt: reservation.updatedAt
                )
            )
            reservation = reservation.updatingTables(result.tables, updatedAt: result.updatedAt)
            await loadTableOptions()
            return true
        } catch let error as APIError {
            errorMessage = error.isConflict
                ? "Rezervasyon başka bir cihazda değişti. Host Masası listesinden güncel kaydı yeniden açın."
                : error.message
            return false
        } catch {
            errorMessage = "Masa ataması kaydedilemedi. Tekrar denemeden önce listeyi yenileyin."
            return false
        }
    }

    func updateServiceStatus(_ serviceStatus: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let result: ReservationServiceStatusUpdate = try await api.put(
                "/reservations/\(venueID)/\(reservation.id)/service-status",
                body: ServiceStatusRequest(
                    serviceStatus: serviceStatus,
                    expectedUpdatedAt: reservation.updatedAt
                )
            )
            reservation = reservation.updatingServiceStatus(result)
            return true
        } catch let error as APIError {
            errorMessage = error.isConflict
                ? "Rezervasyon başka bir cihazda değişti. Host Masası listesinden güncel kaydı yeniden açın."
                : error.message
            return false
        } catch {
            errorMessage = "Servis durumu güncellenemedi. Tekrar denemeden önce listeyi yenileyin."
            return false
        }
    }
}

struct ReservationDetailView: View {
    @StateObject private var model: ReservationDetailViewModel
    @State private var confirmation: ServiceAction?
    @State private var completionMessage: String?
    @State private var feedbackTrigger = 0

    init(reservation: Reservation, venueID: Int) {
        _model = StateObject(wrappedValue: ReservationDetailViewModel(reservation: reservation, venueID: venueID))
    }

    var body: some View {
        List {
            Section {
                header
                    .mpPlainRow(vertical: 4)
            }

            if let errorMessage = model.errorMessage {
                Section {
                    MPNotice(message: errorMessage)
                        .mpPlainRow()
                }
            }

            if let note = model.reservation.note,
               !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Misafir notu") {
                    Label {
                        Text(note)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "text.quote")
                            .foregroundStyle(MP.attention)
                    }
                    .padding(.vertical, 2)
                }
            }

            tableSection

            if model.reservation.checkedIn {
                serviceSection
            } else {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Servis adımları check-in sonrası açılır")
                                .font(.subheadline.weight(.semibold))
                            Text("Misafir geldiğinde Host Masası'ndan geliş kaydını tamamlayın.")
                                .font(.footnote)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.clock")
                            .foregroundStyle(MP.attention)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                LabeledContent("Rezervasyon kodu") {
                    Text(String(model.reservation.uuid.suffix(8)).uppercased())
                        .font(.footnote.monospaced().weight(.semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                }
                LabeledContent("Durum") {
                    Text(model.reservation.status.localizedReservationStatus)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MP.background)
        .navigationTitle("Rezervasyon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let phoneURL = model.reservation.phoneURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: phoneURL) {
                        Image(systemName: "phone.fill")
                    }
                    .accessibilityLabel("Misafiri ara")
                }
            }
        }
        .task { await model.loadTableOptions() }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Durumu güncelle") {
                guard let action = confirmation else { return }
                confirmation = nil
                Task {
                    if await model.updateServiceStatus(action.rawValue) {
                        completionMessage = "Servis durumu güncellendi."
                        feedbackTrigger += 1
                    }
                }
            }
        } message: {
            Text(confirmation?.confirmationMessage ?? "")
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
    }

    // MARK: Header

    private var header: some View {
        let reservation = model.reservation
        let status = reservation.operationBadge()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.displayName)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(.label))
                    if !reservation.customerPhone.isEmpty {
                        Text(reservation.customerPhone)
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                Spacer(minLength: 0)
                MPPill(text: status.text, tone: status.tone)
            }

            HStack(spacing: 0) {
                headerFact(value: reservation.shortTime, label: "bitiş \(reservation.endTime.prefix(5))", systemImage: "clock")
                headerFact(value: "\(reservation.guestCount)", label: "kişi", systemImage: "person.2")
                headerFact(
                    value: reservation.hasTable ? reservation.tableSummary : "—",
                    label: reservation.hasTable ? "masa" : "masa bekliyor",
                    systemImage: "tablecells",
                    tone: reservation.hasTable ? nil : .attention
                )
            }
        }
        .mpCard()
    }

    private func headerFact(value: String, label: String, systemImage: String, tone: MPTone? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone?.color ?? Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tables

    private var tableSection: some View {
        Section {
            if model.isLoadingTables {
                MPLoadingRow(title: "Uygun masalar kontrol ediliyor")
                    .mpPlainRow()
            } else if model.tableOptions.isEmpty {
                VStack(spacing: 10) {
                    Text("Uygun masa bilgisi alınamadı.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                    Button("Yeniden yükle") {
                        Task { await model.loadTableOptions() }
                    }
                    .buttonStyle(MPSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(model.tableOptions) { table in
                        tableChip(table)
                    }
                }
                .mpPlainRow(vertical: 2)

                Button {
                    Task {
                        if await model.saveTables() {
                            completionMessage = "Masa ataması kaydedildi."
                            feedbackTrigger += 1
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if model.isSaving { ProgressView().tint(MP.onBrand) }
                        Text(model.isSaving ? "Kaydediliyor…" : "Masa atamasını kaydet")
                    }
                }
                .buttonStyle(MPPrimaryButtonStyle())
                .disabled(model.isSaving || !hasTableChanges)
                .opacity(hasTableChanges ? 1 : 0.5)
                .mpPlainRow(vertical: 6)
            }
        } header: {
            HStack {
                Text("Masa")
                Spacer()
                Text(selectionDetail)
            }
        } footer: {
            if !model.tableOptions.isEmpty {
                Label("Yıldızlı masalar kişi sayısına uygun öneridir.", systemImage: "sparkles")
            }
        }
    }

    private func tableChip(_ table: AssignableTable) -> some View {
        let isSelected = model.selectedTableIDs.contains(table.id)
        let isEnabled = table.isAvailable || table.isCurrent

        return Button {
            toggle(table)
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
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MP.onBrand)
                    }
                }
                Text(table.detailText)
                    .font(.caption)
                    .foregroundStyle(isSelected ? MP.onBrand.opacity(0.8) : Color(.secondaryLabel))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? MP.brand : MP.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(MP.separator, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel("\(table.name), \(table.detailText)\(table.isRecommended ? ", önerilen" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Service flow

    private var serviceSection: some View {
        Section {
            ForEach(ServiceAction.allCases) { action in
                serviceStep(action)
            }
        } header: {
            Text("Servis akışı")
        } footer: {
            Text("Bir adıma dokunarak servis durumunu güncelleyin.")
        }
    }

    private func serviceStep(_ action: ServiceAction) -> some View {
        let currentIndex = ServiceAction.index(of: model.reservation.serviceStatus)
        let index = ServiceAction.allCases.firstIndex(of: action) ?? 0
        let isCurrent = index == currentIndex
        let isDone = index < currentIndex
        let isNext = index == currentIndex + 1

        return Button {
            confirmation = action
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? action.tone.color : (isDone ? MP.positive.opacity(0.15) : MP.fill))
                    Image(systemName: isDone ? "checkmark" : action.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isCurrent ? Color.white : (isDone ? MP.positive : Color(.secondaryLabel)))
                }
                .frame(width: 30, height: 30)

                Text(action.title)
                    .font(.body.weight(isCurrent || isNext ? .semibold : .regular))
                    .foregroundStyle(isDone ? Color(.secondaryLabel) : Color(.label))

                Spacer()

                if isCurrent {
                    Text("Şu an")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(action.tone.color)
                } else if isNext {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(MP.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving || isCurrent)
        .accessibilityLabel("\(action.title)\(isCurrent ? ", mevcut durum" : "")")
    }

    // MARK: Helpers

    private var selectionDetail: String {
        model.selectedTableIDs.isEmpty ? "Seçilmedi" : "\(model.selectedTableIDs.count) masa seçili"
    }

    private var hasTableChanges: Bool {
        !model.selectedTableIDs.isEmpty
            && model.selectedTableIDs != Set(model.tableOptions.filter(\.isCurrent).map(\.id))
    }

    private func toggle(_ table: AssignableTable) {
        withAnimation(.snappy(duration: 0.18)) {
            if model.selectedTableIDs.contains(table.id) {
                model.selectedTableIDs.remove(table.id)
            } else {
                model.selectedTableIDs.insert(table.id)
            }
        }
    }
}

private enum ServiceAction: String, CaseIterable, Identifiable {
    case arrived = "ARRIVED"
    case seated = "SEATED"
    case bill = "BILL"
    case left = "LEFT"
    case cleaning = "CLEANING"
    case empty = "EMPTY"

    var id: String { rawValue }

    static func index(of serviceStatus: String?) -> Int {
        guard let serviceStatus,
              let action = ServiceAction(rawValue: serviceStatus.uppercased()),
              let index = allCases.firstIndex(of: action) else {
            return 0
        }
        return index
    }

    var title: String {
        switch self {
        case .arrived: "Geldi"
        case .seated: "Masaya oturdu"
        case .bill: "Hesap istendi"
        case .left: "Ayrıldı"
        case .cleaning: "Masa temizleniyor"
        case .empty: "Masa boşaldı"
        }
    }

    var symbol: String {
        switch self {
        case .arrived: "figure.walk.arrival"
        case .seated: "chair.lounge"
        case .bill: "creditcard"
        case .left: "figure.walk.departure"
        case .cleaning: "sparkles"
        case .empty: "circle.dashed"
        }
    }

    var tone: MPTone {
        switch self {
        case .arrived, .seated: .positive
        case .bill: .attention
        case .left, .cleaning: .info
        case .empty: .brand
        }
    }

    var confirmationMessage: String {
        "Servis durumu ‘\(title)’ olarak güncellenecek."
    }
}

private extension AssignableTable {
    var detailText: String {
        let zoneSuffix = zone.map { " · \($0)" } ?? ""
        return "\(capacity) kişilik\(zoneSuffix)"
    }
}

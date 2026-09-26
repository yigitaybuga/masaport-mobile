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

    func updateDetails(customerName: String, customerPhone: String, guestCount: Int, note: String, startTime: String? = nil) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameChanged = customerName != reservation.customerName
        let phoneChanged = customerPhone != reservation.customerPhone
        do {
            let _: EmptyResponse = try await api.put(
                "/reservations/\(venueID)/\(reservation.id)",
                body: ReservationUpdateRequest(
                    customerName: nameChanged || phoneChanged ? customerName : nil,
                    customerPhone: nameChanged || phoneChanged ? customerPhone : nil,
                    guestCount: guestCount,
                    note: trimmedNote,
                    startTime: startTime,
                    expectedUpdatedAt: reservation.updatedAt
                )
            )
            // Sunucu güncel `updatedAt` döndürmez; çakışma kontrolü için kaydı yeniden çek.
            if let fresh: Reservation = try? await api.get("/reservations/\(venueID)/\(reservation.id)") {
                reservation = fresh
            } else {
                let duration = OperationDate.minutesBetween(reservation.startTime, reservation.endTime) ?? 90
                reservation = reservation.updating(
                    customerName: customerName, customerPhone: customerPhone, guestCount: guestCount,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    startTime: startTime, endTime: startTime.map { OperationDate.timeString(adding: duration, to: $0) },
                    updatedAt: reservation.updatedAt
                )
            }
            await loadTableOptions()
            return true
        } catch let error as APIError {
            errorMessage = error.code == "TABLE_CONFLICT"
                ? (error.detail ?? error.message)
                : (error.isConflict
                    ? "Rezervasyon başka bir cihazda değişti. Host Masası listesinden güncel kaydı yeniden açın."
                    : (error.detail ?? error.message))
            return false
        } catch {
            errorMessage = "Rezervasyon güncellenemedi. Tekrar denemeden önce listeyi yenileyin."
            return false
        }
    }

    func updateStatus(_ status: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let _: EmptyResponse = try await api.put(
                "/reservations/\(venueID)/\(reservation.id)/status",
                body: ReservationStatusRequest(status: status, expectedUpdatedAt: reservation.updatedAt)
            )
            reservation = reservation.updating(status: status, updatedAt: ISO8601DateFormatter().string(from: .now))
            return true
        } catch let error as APIError {
            errorMessage = error.isConflict
                ? "Rezervasyon başka bir cihazda değişti. Host Masası listesinden güncel kaydı yeniden açın."
                : (error.detail ?? error.message)
            return false
        } catch {
            errorMessage = "Rezervasyon durumu güncellenemedi. Tekrar denemeden önce listeyi yenileyin."
            return false
        }
    }

    func markNoShow(reason: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let _: EmptyResponse = try await api.post(
                "/reservations/\(venueID)/\(reservation.id)/no-show",
                body: ReservationNoShowRequest(reason: reason, expectedUpdatedAt: reservation.updatedAt)
            )
            reservation = reservation.updating(status: "NO_SHOW", updatedAt: ISO8601DateFormatter().string(from: .now))
            return true
        } catch let error as APIError {
            errorMessage = error.isConflict
                ? (error.code == "NO_SHOW_NOT_ALLOWED" ? "Yalnızca gelmemiş onaylı ya da bekleyen rezervasyon gelmedi olarak işaretlenebilir." : "Rezervasyon başka bir cihazda değişti. Host Masası listesinden güncel kaydı yeniden açın.")
                : (error.detail ?? error.message)
            return false
        } catch {
            errorMessage = "Gelmedi kaydı oluşturulamadı. Tekrar denemeden önce listeyi yenileyin."
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
    @State private var statusAction: StatusAction?
    @State private var showsNoShowSheet = false
    @State private var showsEditSheet = false

    init(reservation: Reservation, venueID: Int) {
        _model = StateObject(wrappedValue: ReservationDetailViewModel(reservation: reservation, venueID: venueID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let errorMessage = model.errorMessage {
                    MPNotice(message: errorMessage)
                }

                if let note = model.reservation.note,
                   !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    noteCard(note)
                }

                if model.reservation.isTerminal {
                    closedCard
                } else {
                    tableSection

                    if model.reservation.checkedIn {
                        serviceSection
                    } else {
                        lockedServiceCard
                    }

                    if model.reservation.canBeClosedByStaff {
                        actionsSection
                    }
                }

                infoSection
            }
            .padding(.horizontal, MP.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(MP.background)
        .navigationTitle("Rezervasyon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !model.reservation.isTerminal {
                    Button {
                        showsEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Rezervasyonu düzenle")
                }
                if let phoneURL = model.reservation.phoneURL {
                    Link(destination: phoneURL) {
                        Image(systemName: "phone.fill")
                    }
                    .accessibilityLabel("Misafiri ara")
                }
            }
        }
        .sheet(isPresented: $showsEditSheet) {
            ReservationEditSheet(reservation: model.reservation, isSaving: model.isSaving) { name, phone, guests, note, startTime in
                if await model.updateDetails(customerName: name, customerPhone: phone, guestCount: guests, note: note, startTime: startTime) {
                    completionMessage = "Rezervasyon bilgileri güncellendi."
                    feedbackTrigger += 1
                    return true
                }
                return false
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
        .confirmationDialog(
            statusAction?.title ?? "",
            isPresented: Binding(get: { statusAction != nil }, set: { if !$0 { statusAction = nil } }),
            titleVisibility: .visible
        ) {
            if let action = statusAction {
                Button(action.confirmTitle, role: action.isDestructive ? .destructive : nil) {
                    statusAction = nil
                    Task {
                        if await model.updateStatus(action.rawValue) {
                            completionMessage = action.completionMessage
                            feedbackTrigger += 1
                        }
                    }
                }
            }
        } message: {
            Text(statusAction?.message(for: model.reservation) ?? "")
        }
        .sheet(isPresented: $showsNoShowSheet) {
            NoShowReasonSheet(guestName: model.reservation.displayName) { reason in
                Task {
                    if await model.markNoShow(reason: reason) {
                        completionMessage = "Rezervasyon gelmedi olarak işaretlendi; masa serbest bırakıldı."
                        feedbackTrigger += 1
                    }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let reservation = model.reservation
        let status = reservation.operationBadge()
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                MPAvatar(name: reservation.displayName, size: 56, tone: status.tone == .neutral ? .brand : status.tone)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.displayName)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(2)
                    if !reservation.customerPhone.isEmpty {
                        Text(reservation.customerPhone)
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    MPPill(text: status.text, tone: status.tone)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                headerFact(value: reservation.shortTime, label: "Bitiş \(reservation.endTime.prefix(5))", systemImage: "clock.fill")
                headerFact(value: "\(reservation.guestCount)", label: "Kişi", systemImage: "person.2.fill")
                headerFact(
                    value: reservation.hasTable ? reservation.tableSummary : "—",
                    label: reservation.hasTable ? "Masa" : "Masa bekliyor",
                    systemImage: "tablecells.fill",
                    tone: reservation.hasTable ? nil : .attention
                )
            }

            if reservation.phoneURL != nil || reservation.smsURL != nil {
                HStack(spacing: 10) {
                    if let phoneURL = reservation.phoneURL {
                        Link(destination: phoneURL) {
                            Label("Ara", systemImage: "phone.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MPSecondaryButtonStyle())
                    }
                    if let smsURL = reservation.smsURL {
                        Link(destination: smsURL) {
                            Label("Mesaj", systemImage: "message.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MPSecondaryButtonStyle())
                    }
                }
            }
        }
        .mpCard()
    }

    private func headerFact(value: String, label: String, systemImage: String, tone: MPTone? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone?.color ?? MP.brand)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone?.color ?? Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MP.fill, in: RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Misafir notu", systemImage: "text.quote", tone: .attention)
            Text(note)
                .font(.body)
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mpCard()
        }
    }

    // MARK: Tables

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Masa ataması", systemImage: "tablecells.fill", detail: selectionDetail)
            VStack(alignment: .leading, spacing: 14) {
                if model.isLoadingTables {
                    MPLoadingRow(title: "Uygun masalar kontrol ediliyor")
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

                    Label("Yıldızlı masalar kişi sayısına uygun öneridir.", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))

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
                }
            }
            .mpCard()
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
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
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
            .background(isSelected ? MP.brand : MP.fill, in: RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : MP.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel("\(table.name), \(table.detailText)\(table.isRecommended ? ", önerilen" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Service flow

    private var lockedServiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Servis akışı", systemImage: "list.bullet.clipboard.fill")
            HStack(spacing: 12) {
                MPIconTile(systemImage: "person.crop.circle.badge.clock", tone: .attention, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Check-in ile misafir oturdu olarak işaretlenir")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.label))
                    Text("QR okutun veya Host Masası'ndan Oturdu işlemini kullanın.")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .mpCard()
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Servis akışı", systemImage: "list.bullet.clipboard.fill", detail: currentServiceTitle)
            VStack(spacing: 0) {
                ForEach(Array(ServiceAction.allCases.enumerated()), id: \.element.id) { index, action in
                    serviceStep(action, index: index)
                }
                Text("Misafir ayrıldığında Kalktı olarak işaretleyin; masa otomatik boşalır.")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mpCard()
        }
    }

    private var currentServiceTitle: String? {
        let index = ServiceAction.index(of: model.reservation.serviceStatus)
        return ServiceAction.allCases.indices.contains(index) ? ServiceAction.allCases[index].title : nil
    }

    private func serviceStep(_ action: ServiceAction, index: Int) -> some View {
        let currentIndex = ServiceAction.index(of: model.reservation.serviceStatus)
        let isCurrent = index == currentIndex
        let isDone = index < currentIndex
        let isNext = index == currentIndex + 1
        let isLast = index == ServiceAction.allCases.count - 1
        let rowHeight: CGFloat = 52

        return Button {
            confirmation = action
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(index == 0 ? Color.clear : (isDone || isCurrent ? MP.positive.opacity(0.5) : MP.hairline))
                            .frame(width: 2)
                        Rectangle()
                            .fill(isLast ? Color.clear : (isDone ? MP.positive.opacity(0.5) : MP.hairline))
                            .frame(width: 2)
                    }
                    .frame(height: rowHeight)
                    ZStack {
                        Circle()
                            .fill(isCurrent ? action.tone.color : (isDone ? MP.positive.opacity(0.15) : MP.fill))
                        if isCurrent {
                            Circle()
                                .stroke(action.tone.color.opacity(0.25), lineWidth: 5)
                        }
                        Image(systemName: isDone ? "checkmark" : action.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isCurrent ? Color.white : (isDone ? MP.positive : Color(.secondaryLabel)))
                    }
                    .frame(width: 30, height: 30)
                }
                .frame(width: 32)

                Text(action.title)
                    .font(.body.weight(isCurrent || isNext ? .semibold : .regular))
                    .foregroundStyle(isDone ? Color(.secondaryLabel) : Color(.label))

                Spacer()

                if isCurrent {
                    MPPill(text: "Şu an", tone: action.tone)
                } else if isNext {
                    HStack(spacing: 4) {
                        Text("Sıradaki")
                        Image(systemName: "arrow.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MP.brand)
                }
            }
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving || !isNext || model.reservation.isTerminal)
        .accessibilityLabel("\(action.title)\(isCurrent ? ", mevcut durum" : "")")
    }

    // MARK: Staff actions

    private var actionsSection: some View {
        let reservation = model.reservation
        return VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "İşlemler", systemImage: "slider.horizontal.3")
            VStack(spacing: 10) {
                if reservation.isPending {
                    Button {
                        statusAction = .confirm
                    } label: {
                        Label("Rezervasyonu onayla", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(MPPrimaryButtonStyle(tone: .positive))
                }
                HStack(spacing: 10) {
                    Button {
                        showsNoShowSheet = true
                    } label: {
                        Label("Gelmedi", systemImage: "person.fill.xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MPSecondaryButtonStyle(tone: .attention))
                    Button {
                        statusAction = .cancel
                    } label: {
                        Label("İptal et", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MPSecondaryButtonStyle(tone: .critical))
                }
                Text(reservation.isPending
                     ? "Onay, misafire bildirim gönderir. İptal ve gelmedi işlemleri masayı serbest bırakır."
                     : "Gelmedi kaydı raporlara işlenir; iptal misafire bildirim gönderir.")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mpCard()
            .disabled(model.isSaving)
        }
    }

    private var closedCard: some View {
        let status = model.reservation.status.uppercased()
        let tone: MPTone = status == "COMPLETED" ? .positive : .critical
        let symbol = status == "COMPLETED" ? "checkmark.circle.fill" : (status == "NO_SHOW" ? "person.fill.xmark" : "xmark.circle.fill")
        let title = status == "COMPLETED" ? "Servis tamamlandı" : (status == "NO_SHOW" ? "Misafir gelmedi" : "Rezervasyon iptal edildi")
        let detail = status == "COMPLETED" ? "Bu kayıt için başka işlem gerekmiyor." : "Masa serbest bırakıldı; kayıt raporlarda görünmeye devam eder."
        return HStack(spacing: 12) {
            MPIconTile(systemImage: symbol, tone: tone, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .mpCard()
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Kayıt bilgisi", systemImage: "number")
            VStack(spacing: 0) {
                infoRow(label: "Rezervasyon kodu", value: String(model.reservation.uuid.suffix(8)).uppercased(), monospaced: true)
                Divider()
                infoRow(label: "Durum", value: model.reservation.status.localizedReservationStatus)
                Divider()
                infoRow(label: "Tarih", value: MPDateFormat.displayDate(model.reservation.reservationDate))
                Divider()
                infoRow(label: "Saat aralığı", value: model.reservation.timeRange)
            }
            .mpCard(padding: 0)
        }
    }

    private func infoRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
            Text(value)
                .font(monospaced ? .subheadline.monospaced().weight(.semibold) : .subheadline.weight(.medium))
                .foregroundStyle(Color(.label))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
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


private extension AssignableTable {
    var detailText: String {
        let zoneSuffix = zone.map { " · \($0)" } ?? ""
        return "\(capacity) kişi\(zoneSuffix)"
    }
}

private enum StatusAction: String {
    case confirm = "CONFIRMED"
    case cancel = "CANCELLED"

    var title: String {
        switch self {
        case .confirm: "Rezervasyon onaylansın mı?"
        case .cancel: "Rezervasyon iptal edilsin mi?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .confirm: "Onayla"
        case .cancel: "İptal et"
        }
    }

    var isDestructive: Bool { self == .cancel }

    var completionMessage: String {
        switch self {
        case .confirm: "Rezervasyon onaylandı; misafire bildirim gönderildi."
        case .cancel: "Rezervasyon iptal edildi; masa serbest bırakıldı."
        }
    }

    func message(for reservation: Reservation) -> String {
        switch self {
        case .confirm:
            "\(reservation.displayName) için \(reservation.shortTime) saatindeki \(reservation.guestText) rezervasyon onaylanacak."
        case .cancel:
            "\(reservation.displayName) için \(reservation.shortTime) saatindeki rezervasyon iptal edilecek ve misafire bildirim gidecek."
        }
    }
}

/// Gelmedi işaretlemesi için sebep seçimi.
private struct NoShowReasonSheet: View {
    let guestName: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @FocusState private var isFocused: Bool

    private let quickReasons = ["Telefonla ulaşılamadı", "Aradı, gelemeyeceğini bildirdi", "Bekleme süresi doldu", "Yanlış rezervasyon"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(guestName) için gelmedi kaydı oluşturulacak. Sebep raporlara işlenir.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(quickReasons, id: \.self) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { reason = item }
                        } label: {
                            HStack {
                                Text(item)
                                    .font(.subheadline.weight(reason == item ? .semibold : .regular))
                                    .foregroundStyle(Color(.label))
                                Spacer()
                                if reason == item {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(MP.brand)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(reason == item ? MP.brand.opacity(0.12) : MP.fill, in: RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Başka bir sebep yazın", text: $reason, axis: .vertical)
                    .lineLimit(2...3)
                    .focused($isFocused)
                    .mpCard(padding: 14)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MP.gutter)
            .padding(.top, 8)
            .background(MP.background)
            .navigationTitle("Gelmedi olarak işaretle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onConfirm(reason.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                } label: {
                    Label("Gelmedi olarak işaretle", systemImage: "person.fill.xmark")
                }
                .buttonStyle(MPPrimaryButtonStyle(tone: .attention))
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                .opacity(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? 0.5 : 1)
                .padding(.horizontal, MP.gutter)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .presentationDetents([.large])
    }
}

/// Kişi sayısı, not ve iletişim bilgisi düzenleme.
private struct ReservationEditSheet: View {
    let reservation: Reservation
    let isSaving: Bool
    let onSave: (String, String, Int, String, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var customerName: String
    @State private var customerPhone: String
    @State private var guestCount: Int
    @State private var note: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case name, phone, note }

    @State private var startDate: Date

    init(reservation: Reservation, isSaving: Bool, onSave: @escaping (String, String, Int, String, String?) async -> Bool) {
        self.reservation = reservation
        self.isSaving = isSaving
        self.onSave = onSave
        _customerName = State(initialValue: reservation.customerName)
        _customerPhone = State(initialValue: reservation.customerPhone)
        _guestCount = State(initialValue: reservation.guestCount)
        _note = State(initialValue: reservation.note ?? "")
        let day = OperationDate.apiFormatter.date(from: reservation.reservationDate) ?? .now
        _startDate = State(initialValue: OperationDate.date(onDay: day, time: reservation.startTime) ?? .now)
    }

    private var originalStartTime: String { String(reservation.startTime.prefix(5)) }
    private var selectedStartTime: String { OperationDate.timeString(startDate) }
    private var startTimeChanged: Bool { selectedStartTime != originalStartTime }
    private var durationMinutes: Int { OperationDate.minutesBetween(reservation.startTime, reservation.endTime) ?? 90 }
    private var projectedEndTime: String { OperationDate.timeString(adding: durationMinutes, to: selectedStartTime) }

    private var hasChanges: Bool {
        customerName.trimmingCharacters(in: .whitespacesAndNewlines) != reservation.customerName
            || customerPhone.trimmingCharacters(in: .whitespacesAndNewlines) != reservation.customerPhone
            || guestCount != reservation.guestCount
            || note.trimmingCharacters(in: .whitespacesAndNewlines) != (reservation.note ?? "")
            || startTimeChanged
    }

    private var canSave: Bool {
        hasChanges
            && !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && customerPhone.filter(\.isNumber).count >= 10
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        MPSectionHeader(title: "Misafir", systemImage: "person.fill")
                        VStack(spacing: 0) {
                            field(systemImage: "person", isFocused: focusedField == .name) {
                                TextField("Ad Soyad", text: $customerName)
                                    .textContentType(.name)
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .name)
                            }
                            Divider().padding(.leading, 54)
                            field(systemImage: "phone", isFocused: focusedField == .phone) {
                                TextField("Telefon", text: $customerPhone)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
                                    .focused($focusedField, equals: .phone)
                            }
                        }
                        .mpCard(padding: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        MPSectionHeader(title: "Kişi sayısı", systemImage: "person.2.fill")
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(guestCount) kişi")
                                    .font(.subheadline.weight(.semibold))
                                Text(guestCount != reservation.guestCount ? "Masa uygunluğu yeniden kontrol edilir." : "Rezervasyondaki kayıtlı sayı.")
                                    .font(.caption)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                stepperButton("minus") { if guestCount > 1 { guestCount -= 1 } }
                                    .disabled(guestCount <= 1)
                                Text(guestCount, format: .number)
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .frame(width: 44)
                                    .contentTransition(.numericText())
                                stepperButton("plus") { if guestCount < 40 { guestCount += 1 } }
                                    .disabled(guestCount >= 40)
                            }
                            .background(MP.fill, in: Capsule())
                            .animation(.snappy(duration: 0.18), value: guestCount)
                        }
                        .mpCard(padding: 14)
                    }

                    if !reservation.checkedIn {
                        VStack(alignment: .leading, spacing: 10) {
                            MPSectionHeader(title: "Saat", systemImage: "clock.fill", detail: "Süre \(durationMinutes) dk")
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(selectedStartTime)–\(projectedEndTime)")
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .monospacedDigit()
                                    Text(startTimeChanged ? "Bitiş aynı süreyle kaydırılır; masa uygunluğu sunucuda kontrol edilir." : "Rezervasyondaki kayıtlı saat.")
                                        .font(.caption)
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                                Spacer()
                                DatePicker("Başlangıç", selection: $startDate, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .environment(\.timeZone, TimeZone(identifier: "Europe/Istanbul")!)
                                    .environment(\.locale, Locale(identifier: "tr_TR"))
                            }
                            .mpCard(padding: 14)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        MPSectionHeader(title: "Misafir notu", systemImage: "text.quote")
                        TextField("Alerji, özel istek, kutlama…", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($focusedField, equals: .note)
                            .mpCard(padding: 14)
                    }

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
            .navigationTitle("Rezervasyonu düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    focusedField = nil
                    Task { await save() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(MP.onBrand) }
                        Text(isSubmitting ? "Kaydediliyor…" : "Değişiklikleri kaydet")
                    }
                }
                .buttonStyle(MPPrimaryButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .padding(.horizontal, MP.gutter)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    private func save() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let succeeded = await onSave(
            customerName.trimmingCharacters(in: .whitespacesAndNewlines),
            customerPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            guestCount,
            note,
            startTimeChanged ? selectedStartTime : nil
        )
        if succeeded {
            dismiss()
        } else {
            errorMessage = "Değişiklikler kaydedilemedi. Detay ekranındaki uyarıyı kontrol edin."
        }
    }

    private func field<Content: View>(systemImage: String, isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            MPIconTile(systemImage: systemImage, tone: isFocused ? .brand : .neutral, size: 28)
            content().font(.body)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .animation(.easeOut(duration: 0.15), value: isFocused)
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
}

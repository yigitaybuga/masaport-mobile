import SwiftUI

struct HostDeskView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = HostDeskViewModel()
    @StateObject private var liveUpdates = HostDeskLiveUpdates()
    @State private var searchText = ""
    @State private var selectedFilter: DeskFilter = .all
    @State private var checkInCandidate: Reservation?
    @State private var earlyCheckIn: (reservation: Reservation, message: String)?
    @State private var checkInSuccessCount = 0
    @State private var showsScanner = false
    @State private var showsWalkIn = false
    @State private var showsDatePicker = false
    @State private var showsWaitlist = false
    @State private var serviceCandidate: (reservation: Reservation, action: ServiceAction)?
    @State private var moveCandidate: (reservation: Reservation, table: VenueTable)?
    @State private var viewMode: DeskViewMode = .list
    @State private var openedReservation: Reservation?
    @StateObject private var searchHistory = SearchHistoryStore(scope: "host-desk")
    @State private var selectedDate: Date = .now

    private var isToday: Bool { OperationDate.isToday(selectedDate) }

    var body: some View {
        NavigationStack {
            Group {
                if let venue = session.activeVenue {
                    content(for: venue)
                } else {
                    ContentUnavailableView("Mekan bulunamadı", systemImage: "building.2")
                }
            }
            .background(MP.background)
            .navigationTitle("Host Masası")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsWalkIn = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Walk-in misafir ekle")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    QRScanButton(isPresented: $showsScanner)
                    VenueMenu()
                }
            }
            .fullScreenCover(isPresented: $showsScanner) {
                CheckinScannerView {
                    if let venueID = session.activeVenue?.id {
                        Task { await model.load(venueID: venueID, date: selectedDate) }
                    }
                }
            }
            .sheet(isPresented: $showsWalkIn) {
                if let venueID = session.activeVenue?.id {
                    WalkInView(venueID: venueID) { _ in
                        selectedDate = .now
                        Task { await model.load(venueID: venueID, date: .now) }
                    }
                }
            }
            .sheet(isPresented: $showsDatePicker) {
                HostDeskDatePickerSheet(selection: $selectedDate)
            }
            .navigationDestination(isPresented: $showsWaitlist) {
                WaitlistView()
            }
            .confirmationDialog(
                "Misafir geldi mi?",
                isPresented: Binding(
                    get: { checkInCandidate != nil },
                    set: { if !$0 { checkInCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Check-in yap") {
                    guard let reservation = checkInCandidate, let venueID = session.activeVenue?.id else { return }
                    checkInCandidate = nil
                    Task { await performCheckIn(reservation, venueID: venueID, force: false) }
                }
            } message: {
                Text("\(checkInCandidate?.displayName ?? "Misafir") için geliş kaydı oluşturulacak.")
            }
            .confirmationDialog(
                "Erken check-in",
                isPresented: Binding(
                    get: { earlyCheckIn != nil },
                    set: { if !$0 { earlyCheckIn = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Yine de check-in yap") {
                    guard let early = earlyCheckIn, let venueID = session.activeVenue?.id else { return }
                    earlyCheckIn = nil
                    Task { await performCheckIn(early.reservation, venueID: venueID, force: true) }
                }
            } message: {
                Text(earlyCheckIn?.message ?? "")
            }
            .confirmationDialog(
                serviceCandidate?.action.title ?? "",
                isPresented: Binding(
                    get: { serviceCandidate != nil },
                    set: { if !$0 { serviceCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Durumu güncelle") {
                    guard let candidate = serviceCandidate, let venueID = session.activeVenue?.id else { return }
                    serviceCandidate = nil
                    Task {
                        if await model.updateServiceStatus(candidate.reservation, to: candidate.action, venueID: venueID, date: selectedDate) {
                            checkInSuccessCount += 1
                        }
                    }
                }
            } message: {
                if let candidate = serviceCandidate {
                    Text("\(candidate.reservation.displayName) · \(candidate.reservation.tableSummary): \(candidate.action.confirmationMessage)")
                }
            }
            .confirmationDialog(
                "Masa değiştirilsin mi?",
                isPresented: Binding(
                    get: { moveCandidate != nil },
                    set: { if !$0 { moveCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Masa \(moveCandidate?.table.name ?? "")'e taşı") {
                    guard let candidate = moveCandidate, let venueID = session.activeVenue?.id else { return }
                    moveCandidate = nil
                    Task {
                        if await model.assignTable(candidate.reservation, to: candidate.table, venueID: venueID, date: selectedDate) {
                            checkInSuccessCount += 1
                        }
                    }
                }
            } message: {
                if let candidate = moveCandidate {
                    Text(moveMessage(candidate.reservation, candidate.table))
                }
            }
            .navigationDestination(item: $openedReservation) { reservation in
                if let venueID = session.activeVenue?.id {
                    ReservationDetailView(reservation: reservation, venueID: venueID)
                        .onDisappear { Task { await model.load(venueID: venueID, date: selectedDate) } }
                }
            }
            .sensoryFeedback(.success, trigger: checkInSuccessCount)
        }
    }

    private func moveMessage(_ reservation: Reservation, _ table: VenueTable) -> String {
        var parts: [String] = []
        if reservation.hasTable {
            parts.append("\(reservation.displayName) \(reservation.tableSummary) yerine \(table.name) masasına alınacak.")
        } else {
            parts.append("\(reservation.displayName) \(table.name) masasına atanacak.")
        }
        if table.capacity < reservation.guestCount {
            parts.append("Dikkat: masa \(table.capacity) kişilik, rezervasyon \(reservation.guestText).")
        }
        if let current = model.reservations.first(where: { $0.id != reservation.id && !$0.isTerminal && $0.isInside && $0.tables.contains { $0.id == table.id } }) {
            parts.append("Masada şu an \(current.displayName) oturuyor; sunucu çakışmayı reddedebilir.")
        }
        return parts.joined(separator: " ")
    }

    private func performCheckIn(_ reservation: Reservation, venueID: Int, force: Bool) async {
        switch await model.checkIn(reservation, venueID: venueID, date: selectedDate, force: force) {
        case .completed:
            checkInSuccessCount += 1
        case .earlyCheckInRequired(let message):
            earlyCheckIn = (reservation, message)
        case .failed:
            break
        }
    }

    private func content(for venue: Venue) -> some View {
        Group {
            if viewMode == .floor {
                floorContent(for: venue)
            } else {
                listContent(for: venue)
            }
        }
        .refreshable { await model.load(venueID: venue.id, date: selectedDate) }
        .task(id: "\(venue.id)-\(session.accessToken ?? "")-\(OperationDate.apiString(selectedDate))") {
            await model.load(venueID: venue.id, date: selectedDate)
            liveUpdates.onChange = { event in
                guard event.venueID == venue.id else { return }
                Task { await model.load(venueID: venue.id, date: selectedDate) }
            }
            if let accessToken = session.accessToken {
                liveUpdates.connect(venueID: venue.id, accessToken: accessToken)
            }
        }
        .onDisappear { liveUpdates.disconnect() }
    }

    private func floorContent(for venue: Venue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dateBar
                if isToday && !model.reservations.isEmpty {
                    deskSummary
                }
                if let errorMessage = model.errorMessage {
                    MPNotice(message: errorMessage, actionTitle: "Yenile") {
                        Task { await model.load(venueID: venue.id, date: selectedDate) }
                    }
                }
                if model.isLoading && model.tables.isEmpty {
                    MPLoadingRow(title: "Salon planı yükleniyor").mpCard()
                } else if model.tables.isEmpty {
                    MPEmptyState(systemImage: "tablecells", title: "Masa planı yok", message: "Masalar web panelinden tanımlanır.")
                        .mpCard(padding: 0)
                } else {
                    HostDeskFloorView(
                        tables: model.tables,
                        reservations: model.reservations,
                        busyReservationID: model.checkingInReservationID,
                        onMove: { reservation, table in moveCandidate = (reservation, table) },
                        onOpen: { reservation in openedReservation = reservation }
                    )
                }
            }
            .padding(.horizontal, MP.gutter)
            .padding(.top, 6)
            .padding(.bottom, 32)
        }
    }

    private func listContent(for venue: Venue) -> some View {
        List {
            dateBar
                .mpPlainRow(vertical: 2)

            if isToday && !model.reservations.isEmpty {
                deskSummary
                    .mpPlainRow(vertical: 4)
            }

            filterBar
                .mpPlainRow(vertical: 6)

            if let errorMessage = model.errorMessage {
                MPNotice(message: errorMessage, actionTitle: "Yenile") {
                    Task { await model.load(venueID: venue.id, date: selectedDate) }
                }
                .mpPlainRow(vertical: 4)
            }

            if model.isLoading && model.reservations.isEmpty {
                MPLoadingRow(title: "Rezervasyonlar ve canlı bağlantı hazırlanıyor")
                    .mpPlainRow()
            } else if groupedReservations.isEmpty {
                MPEmptyState(
                    systemImage: searchText.isEmpty ? "person.2.slash" : "magnifyingglass",
                    title: searchText.isEmpty ? (isToday ? "Bu görünümde kayıt yok" : "\(dateTitle(selectedDate)) için rezervasyon yok") : "Eşleşen misafir bulunamadı",
                    message: searchText.isEmpty ? "Filtreyi değiştirin veya listeyi aşağı çekerek yenileyin." : "Ad, telefon veya rezervasyon kodu ile arayın."
                )
                .mpCard(padding: 0)
                .mpPlainRow(vertical: 4)
            } else {
                ForEach(groupedReservations, id: \.state.sectionOrder) { group in
                    Section {
                        ForEach(group.reservations) { reservation in
                            row(reservation, venueID: venue.id)
                        }
                    } header: {
                        MPListSectionHeader(title: group.state.sectionTitle, count: group.reservations.count, tone: group.state.sectionTone)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Misafir, telefon veya kod")
        .searchSuggestions {
            HostDeskSearchSuggestions(
                query: searchText,
                history: searchHistory,
                candidates: model.reservations.map(\.customerName)
            )
        }
        .onSubmit(of: .search) {
            searchHistory.record(searchText)
        }
    }

    // MARK: Date

    private var dateBar: some View {
        HStack(spacing: 8) {
            dateChip(title: "Bugün", isSelected: isToday) { selectedDate = .now }
            dateChip(title: "Yarın", isSelected: OperationDate.isTomorrow(selectedDate)) {
                selectedDate = OperationDate.calendar.date(byAdding: .day, value: 1, to: OperationDate.startOfDay(.now)) ?? .now
            }
            Button {
                showsDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                    Text(isToday || OperationDate.isTomorrow(selectedDate) ? "Tarih seç" : dateTitle(selectedDate))
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 13)
                .frame(height: 34)
                .foregroundStyle(isCustomDate ? MP.onBrand : Color(.label))
                .background(isCustomDate ? MP.brand : MP.fill, in: Capsule())
                .overlay { if !isCustomDate { Capsule().strokeBorder(MP.hairline, lineWidth: 1) } }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tarih seç")
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy(duration: 0.2)) { viewMode = viewMode == .list ? .floor : .list }
            } label: {
                Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewMode == .floor ? MP.onBrand : MP.brand)
                    .frame(width: 36, height: 34)
                    .background(viewMode == .floor ? MP.brand : MP.brand.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewMode == .list ? "Salon görünümüne geç" : "Liste görünümüne geç")
            Button {
                showsWaitlist = true
            } label: {
                Image(systemName: "hourglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MP.brand)
                    .frame(width: 36, height: 34)
                    .background(MP.brand.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bekleme listesi")
        }
    }

    private var isCustomDate: Bool { !isToday && !OperationDate.isTomorrow(selectedDate) }

    private func dateChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 13)
                .frame(height: 34)
                .foregroundStyle(isSelected ? MP.onBrand : Color(.label))
                .background(isSelected ? MP.brand : MP.fill, in: Capsule())
                .overlay { if !isSelected { Capsule().strokeBorder(MP.hairline, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dateTitle(_ date: Date) -> String {
        MPDateFormat.shortDay.string(from: date)
    }

    // MARK: Summary

    private var deskSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                MPProgressRing(progress: arrivalProgress, lineWidth: 6, tone: .positive)
                VStack(spacing: -1) {
                    Text(arrivedCount, format: .number)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ \(expectedCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .frame(width: 58, height: 58)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Karşılanan misafir \(arrivedCount) / \(expectedCount)")

            VStack(alignment: .leading, spacing: 3) {
                Text("Karşılanan misafir")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text(summaryDetail)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                MPLiveIndicator(isConnected: liveUpdates.state == .connected)
                if overdueCount > 0 {
                    MPPill(text: "\(overdueCount) geciken", tone: .critical)
                } else if insideCount > 0 {
                    MPPill(text: "\(insideCount) içeride", tone: .positive)
                }
            }
        }
        .mpCard(padding: 14)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DeskFilter.allCases) { filter in
                    MPFilterChip(
                        title: filter.title,
                        count: filter.count(in: model.reservations),
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.snappy(duration: 0.2)) { selectedFilter = filter }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func row(_ reservation: Reservation, venueID: Int) -> some View {
        NavigationLink {
            ReservationDetailView(reservation: reservation, venueID: venueID)
                .onAppear { searchHistory.record(searchText) }
                .onDisappear { Task { await model.load(venueID: venueID, date: selectedDate) } }
        } label: {
            ReservationRow(
                reservation: reservation,
                onCheckIn: { checkInCandidate = reservation },
                isCheckingIn: model.checkingInReservationID == reservation.id
            )
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if reservation.canCheckIn {
                Button {
                    checkInCandidate = reservation
                } label: {
                    Label("Geldi", systemImage: "person.fill.checkmark")
                }
                .tint(MP.positive)
            } else if reservation.isInside, let next = ServiceAction.current(for: reservation.serviceStatus).next {
                Button {
                    serviceCandidate = (reservation, next)
                } label: {
                    Label(next.title, systemImage: next.symbol)
                }
                .tint(next.tone.color)
            }
        }
        .contextMenu {
            if reservation.canCheckIn {
                Button("Check-in yap", systemImage: "person.fill.checkmark") {
                    checkInCandidate = reservation
                }
            }
            if reservation.isInside {
                let current = ServiceAction.current(for: reservation.serviceStatus)
                Section("Servis adımı") {
                    ForEach(ServiceAction.allCases.filter { $0 != current }) { action in
                        Button(action.title, systemImage: action.symbol) {
                            serviceCandidate = (reservation, action)
                        }
                    }
                }
            }
            if let phoneURL = reservation.phoneURL {
                Link(destination: phoneURL) {
                    Label("Ara \(reservation.customerPhone)", systemImage: "phone")
                }
            }
        }
    }

    // MARK: Data

    private var referenceDate: Date { .now }

    private var arrivedCount: Int { model.reservations.count { $0.checkedIn } }

    private var expectedCount: Int {
        model.reservations.count { $0.checkedIn || $0.status.uppercased() == "CONFIRMED" }
    }

    private var arrivalProgress: Double {
        expectedCount == 0 ? 0 : Double(arrivedCount) / Double(expectedCount)
    }

    private var insideCount: Int {
        model.reservations.count {
            if case .inside = $0.operationalState(relativeTo: referenceDate) { return true }
            return false
        }
    }

    private var overdueCount: Int {
        model.reservations.count {
            if case .overdue = $0.operationalState(relativeTo: referenceDate) { return true }
            return false
        }
    }

    private var summaryDetail: String {
        let remaining = max(0, expectedCount - arrivedCount)
        if remaining == 0 { return expectedCount == 0 ? "Bugün onaylı rezervasyon yok." : "Tüm misafirler karşılandı." }
        let guests = model.reservations.filter(\.canCheckIn).reduce(0) { $0 + $1.guestCount }
        return "\(remaining) rezervasyon · \(guests) kişi bekleniyor"
    }

    private var filteredReservations: [Reservation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.reservations.filter { reservation in
            let matchesQuery = query.isEmpty || [
                reservation.customerName,
                reservation.customerPhone,
                reservation.uuid
            ].contains { $0.lowercased().contains(query) }
            return matchesQuery && selectedFilter.matches(reservation)
        }
    }

    private var groupedReservations: [(state: ReservationOperationalState, reservations: [Reservation])] {
        let referenceDate = Date.now
        var buckets: [Int: (state: ReservationOperationalState, reservations: [Reservation])] = [:]
        for reservation in filteredReservations {
            let state = reservation.operationalState(relativeTo: referenceDate)
            let key = state.sectionOrder
            if buckets[key] == nil {
                buckets[key] = (state, [])
            }
            buckets[key]?.reservations.append(reservation)
        }
        return buckets.keys.sorted().compactMap { key in
            guard var group = buckets[key] else { return nil }
            group.reservations.sort { lhs, rhs in
                let left = lhs.startDate() ?? .distantFuture
                let right = rhs.startDate() ?? .distantFuture
                if case .overdue = group.state { return left > right }
                return left < right
            }
            return group
        }
    }
}

private enum DeskFilter: String, CaseIterable, Identifiable {
    case all, arriving, waiting, inside

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .arriving: "Gelecek"
        case .waiting: "Onay"
        case .inside: "İçeride"
        }
    }

    func matches(_ reservation: Reservation) -> Bool {
        switch self {
        case .all:
            return true
        case .arriving:
            return reservation.canCheckIn
        case .waiting:
            return reservation.status.uppercased() == "PENDING"
        case .inside:
            if case .inside = reservation.operationalState() { return true }
            return false
        }
    }

    func count(in reservations: [Reservation]) -> Int {
        reservations.count(where: matches)
    }
}

extension Reservation {
    var phoneURL: URL? {
        let normalized = customerPhone.filter { $0.isNumber || $0 == "+" }
        return normalized.isEmpty ? nil : URL(string: "tel:\(normalized)")
    }

    var smsURL: URL? {
        let normalized = customerPhone.filter { $0.isNumber || $0 == "+" }
        return normalized.isEmpty ? nil : URL(string: "sms:\(normalized)")
    }
}

/// Host Masası için gün seçimi.
private struct HostDeskDatePickerSheet: View {
    @Binding var selection: Date
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date = .now

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("Tarih", selection: $draft, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    .environment(\.timeZone, TimeZone(identifier: "Europe/Istanbul")!)
                    .tint(MP.brand)
                    .mpCard(padding: 8)
                Button("Bu günü göster") {
                    selection = draft
                    dismiss()
                }
                .buttonStyle(MPPrimaryButtonStyle())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MP.gutter)
            .padding(.top, 8)
            .background(MP.background)
            .navigationTitle("Tarih seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .onAppear { draft = selection }
        }
        .presentationDetents([.medium, .large])
    }
}

private enum DeskViewMode { case list, floor }

/// Arama önerileri: yazarken eşleşen misafirler, boşken son aramalar.
struct HostDeskSearchSuggestions: View {
    let query: String
    @ObservedObject var history: SearchHistoryStore
    let candidates: [String]

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !history.queries.isEmpty {
                Section {
                    ForEach(history.queries, id: \.self) { item in
                        Label(item, systemImage: "clock.arrow.circlepath")
                            .searchCompletion(item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { history.remove(item) } label: { Label("Sil", systemImage: "trash") }
                            }
                    }
                } header: {
                    HStack {
                        Text("Son aramalar")
                        Spacer()
                        Button("Temizle") { history.clear() }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                    }
                }
            }
        } else {
            let matches = Array(
                Set(candidates.filter { !$0.isEmpty && $0.localizedCaseInsensitiveContains(trimmed) && $0.caseInsensitiveCompare(trimmed) != .orderedSame })
            ).sorted().prefix(6)
            if !matches.isEmpty {
                Section("Misafirler") {
                    ForEach(Array(matches), id: \.self) { name in
                        Label(name, systemImage: "person")
                            .searchCompletion(name)
                    }
                }
            }
        }
    }
}

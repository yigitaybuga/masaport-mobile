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
                    NavigationLink {
                        WaitlistView()
                    } label: {
                        Image(systemName: "hourglass")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Bekleme listesi")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    QRScanButton(isPresented: $showsScanner)
                    VenueMenu()
                }
            }
            .fullScreenCover(isPresented: $showsScanner) {
                CheckinScannerView {
                    if let venueID = session.activeVenue?.id {
                        Task { await model.load(venueID: venueID) }
                    }
                }
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
            .sensoryFeedback(.success, trigger: checkInSuccessCount)
        }
    }

    private func performCheckIn(_ reservation: Reservation, venueID: Int, force: Bool) async {
        switch await model.checkIn(reservation, venueID: venueID, force: force) {
        case .completed:
            checkInSuccessCount += 1
        case .earlyCheckInRequired(let message):
            earlyCheckIn = (reservation, message)
        case .failed:
            break
        }
    }

    private func content(for venue: Venue) -> some View {
        List {
            filterBar
                .mpPlainRow()

            if let errorMessage = model.errorMessage {
                MPNotice(message: errorMessage, actionTitle: "Yenile") {
                    Task { await model.load(venueID: venue.id) }
                }
                .mpPlainRow(vertical: 4)
            }

            if model.isLoading && model.reservations.isEmpty {
                MPLoadingRow(title: "Rezervasyonlar ve canlı bağlantı hazırlanıyor")
                    .mpPlainRow()
            } else if groupedReservations.isEmpty {
                MPEmptyState(
                    systemImage: searchText.isEmpty ? "person.2.slash" : "magnifyingglass",
                    title: searchText.isEmpty ? "Bu görünümde kayıt yok" : "Eşleşen misafir bulunamadı",
                    message: searchText.isEmpty ? "Filtreyi değiştirin veya listeyi aşağı çekerek yenileyin." : "Ad, telefon veya rezervasyon kodu ile arayın."
                )
                .mpPlainRow()
            } else {
                ForEach(groupedReservations, id: \.state.sectionOrder) { group in
                    Section {
                        ForEach(group.reservations) { reservation in
                            row(reservation, venueID: venue.id)
                        }
                    } header: {
                        sectionHeader(group.state, count: group.reservations.count)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Misafir, telefon veya kod")
        .refreshable { await model.load(venueID: venue.id) }
        .task(id: "\(venue.id)-\(session.accessToken ?? "")") {
            await model.load(venueID: venue.id)
            liveUpdates.onChange = { event in
                guard event.venueID == venue.id else { return }
                Task { await model.load(venueID: venue.id) }
            }
            if let accessToken = session.accessToken {
                liveUpdates.connect(venueID: venue.id, accessToken: accessToken)
            }
        }
        .onDisappear { liveUpdates.disconnect() }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
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
            }
            .scrollIndicators(.hidden)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                }
            }
            MPLiveIndicator(isConnected: liveUpdates.state == .connected)
        }
        .padding(.bottom, 4)
    }

    private func sectionHeader(_ state: ReservationOperationalState, count: Int) -> some View {
        HStack(spacing: 6) {
            if case .overdue = state {
                Circle().fill(MP.critical).frame(width: 6, height: 6)
            } else if case .now = state {
                Circle().fill(MP.info).frame(width: 6, height: 6)
            }
            Text(state.sectionTitle)
            Text(count, format: .number)
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    private func row(_ reservation: Reservation, venueID: Int) -> some View {
        NavigationLink {
            ReservationDetailView(reservation: reservation, venueID: venueID)
                .onDisappear { Task { await model.load(venueID: venueID) } }
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
            }
        }
        .contextMenu {
            if reservation.canCheckIn {
                Button("Check-in yap", systemImage: "person.fill.checkmark") {
                    checkInCandidate = reservation
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
}

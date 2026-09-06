import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: OperationNavigation
    @StateObject private var model = TodayViewModel()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if let venue = session.activeVenue {
                    content(for: venue)
                } else {
                    ContentUnavailableView(
                        "Mekan bulunamadı",
                        systemImage: "building.2",
                        description: Text("Bu hesap için operasyon erişimi olan bir mekan yok.")
                    )
                }
            }
            .background(MP.background)
            .navigationTitle("Bugün")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { VenueMenu() }
            }
        }
    }

    private func content(for venue: Venue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MP.brand)
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .padding(.horizontal, 4)

                if let errorMessage = model.errorMessage {
                    MPNotice(message: errorMessage, actionTitle: "Tekrar dene") {
                        Task { await model.load(venue: venue) }
                    }
                } else if model.isLoading && model.reservations.isEmpty {
                    MPLoadingRow(title: "Bugünün akışı yükleniyor")
                        .mpCard()
                } else {
                    statsGrid

                    if !attentionReservations.isEmpty {
                        attentionSection(venueID: venue.id)
                    }

                    upcomingSection(venueID: venue.id)
                }
            }
            .padding(.horizontal, MP.gutter)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load(venue: venue) }
        .task(id: venue.id) { await model.load(venue: venue) }
    }

    // MARK: Stats

    private var statsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MPStatTile(value: model.reservations.count, label: "Rezervasyon", systemImage: "calendar")
            MPStatTile(value: insideCount, label: "İçeride", systemImage: "person.fill.checkmark", tone: .positive)
            MPStatTile(value: overdueCount, label: "Geciken", systemImage: "clock.badge.exclamationmark", tone: .critical)
            NavigationLink {
                WaitlistView()
            } label: {
                MPStatTile(value: model.waitlist.count, label: "Bekleme listesi", systemImage: "hourglass", tone: .attention)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Bekleme listesini açar")
        }
    }

    // MARK: Attention

    private func attentionSection(venueID: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionTitle(title: "Dikkat gerektiren", detail: "\(attentionReservations.count) kayıt")
            VStack(spacing: 0) {
                ForEach(Array(attentionReservations.prefix(4).enumerated()), id: \.element.id) { index, reservation in
                    NavigationLink {
                        ReservationDetailView(reservation: reservation, venueID: venueID)
                    } label: {
                        ReservationRow(reservation: reservation)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < min(attentionReservations.count, 4) - 1 {
                        Divider().padding(.leading, 80)
                    }
                }
                if attentionReservations.count > 4 {
                    Divider().padding(.leading, 14)
                    seeAllButton(title: "Host Masası'nda tümünü gör")
                }
            }
            .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
        }
    }

    // MARK: Upcoming timeline

    private func upcomingSection(venueID: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionTitle(title: "Sıradaki", detail: upcomingReservations.isEmpty ? nil : "\(upcomingReservations.count) rezervasyon")

            if upcomingReservations.isEmpty {
                MPEmptyState(
                    systemImage: model.reservations.isEmpty ? "calendar.badge.checkmark" : "checkmark.circle",
                    title: model.reservations.isEmpty ? "Bugün için rezervasyon yok" : "Sırada bekleyen rezervasyon yok",
                    message: model.reservations.isEmpty ? "Yeni rezervasyonlar burada görünecek." : "Tüm misafirler karşılandı."
                )
                .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(hourGroups, id: \.hour) { group in
                        hourHeader(group.hour)
                        ForEach(Array(group.reservations.enumerated()), id: \.element.id) { index, reservation in
                            NavigationLink {
                                ReservationDetailView(reservation: reservation, venueID: venueID)
                            } label: {
                                ReservationRow(reservation: reservation)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < group.reservations.count - 1 {
                                Divider().padding(.leading, 80)
                            }
                        }
                    }
                    if upcomingReservations.count > visibleUpcoming.count {
                        Divider().padding(.leading, 14)
                        seeAllButton(title: "\(upcomingReservations.count - visibleUpcoming.count) rezervasyon daha")
                    }
                }
                .background(MP.card, in: RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
            }
        }
    }

    private func hourHeader(_ hour: String) -> some View {
        HStack(spacing: 8) {
            Text(hour)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color(.secondaryLabel))
            Rectangle()
                .fill(MP.separator)
                .frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func seeAllButton(title: String) -> some View {
        Button {
            navigation.tab = .hostDesk
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MP.brand)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Derived data

    private var referenceDate: Date { .now }

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

    /// Geciken ve onay bekleyen kayıtlar; en acil olan üstte.
    private var attentionReservations: [Reservation] {
        model.reservations
            .filter {
                switch $0.operationalState(relativeTo: referenceDate) {
                case .overdue, .pending: true
                default: false
                }
            }
            .sorted { lhs, rhs in
                let l = lhs.operationalState(relativeTo: referenceDate)
                let r = rhs.operationalState(relativeTo: referenceDate)
                if l.sortRank != r.sortRank { return l.sortRank < r.sortRank }
                return (lhs.startDate() ?? .distantFuture) < (rhs.startDate() ?? .distantFuture)
            }
    }

    /// Henüz gelmemiş, iptal edilmemiş rezervasyonlar; saat sırasıyla.
    private var upcomingReservations: [Reservation] {
        model.reservations
            .filter {
                switch $0.operationalState(relativeTo: referenceDate) {
                case .now, .upcoming, .later: true
                default: false
                }
            }
            .sorted { ($0.startDate() ?? .distantFuture) < ($1.startDate() ?? .distantFuture) }
    }

    private var visibleUpcoming: [Reservation] { Array(upcomingReservations.prefix(8)) }

    private var hourGroups: [(hour: String, reservations: [Reservation])] {
        var groups: [(hour: String, reservations: [Reservation])] = []
        for reservation in visibleUpcoming {
            let hour = "\(reservation.startTime.prefix(2)):00"
            if let last = groups.indices.last, groups[last].hour == hour {
                groups[last].reservations.append(reservation)
            } else {
                groups.append((hour, [reservation]))
            }
        }
        return groups
    }

    private var greeting: String {
        guard let name = session.user?.name.split(separator: " ").first else {
            return "Günün servis akışı"
        }
        return "İyi çalışmalar, \(name)"
    }

    private var formattedDate: String {
        MPDateFormat.longDay.string(from: Date())
    }
}

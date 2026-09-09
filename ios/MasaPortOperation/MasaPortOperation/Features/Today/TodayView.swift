import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: OperationNavigation
    @StateObject private var model = TodayViewModel()
    @State private var showsScanner = false
    @State private var showsWalkIn = false
    @State private var selectedTable: VenueTable?
    @State private var offerCandidate: WaitlistEntry?
    @State private var offerSuccessCount = 0
    @State private var convertCandidate: WaitlistEntry?

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
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showsScanner) {
                CheckinScannerView {
                    if let venue = session.activeVenue {
                        Task { await model.load(venue: venue) }
                    }
                }
            }
            .sheet(isPresented: $showsWalkIn) {
                if let venue = session.activeVenue {
                    WalkInView(venueID: venue.id) { _ in
                        Task { await model.load(venue: venue) }
                    }
                }
            }
            .confirmationDialog(
                "Masa teklifi gönderilsin mi?",
                isPresented: Binding(get: { offerCandidate != nil }, set: { if !$0 { offerCandidate = nil } }),
                titleVisibility: .visible
            ) {
                Button("Teklif gönder") {
                    guard let entry = offerCandidate, let venue = session.activeVenue else { return }
                    offerCandidate = nil
                    Task {
                        if await model.sendOffer(for: entry, venue: venue) { offerSuccessCount += 1 }
                    }
                }
            } message: {
                Text("\(offerCandidate?.customerName ?? "Misafir") için uygun masa tutulacak ve misafire kabul bağlantısı gönderilecek.")
            }
            .sensoryFeedback(.success, trigger: offerSuccessCount)
            .sheet(item: $convertCandidate) { entry in
                if let venue = session.activeVenue {
                    WalkInView(venueID: venue.id, prefill: entry.walkInPrefill) { _ in
                        Task {
                            if await model.markConverted(entry, venue: venue) { offerSuccessCount += 1 }
                        }
                    }
                }
            }
            .sheet(item: $selectedTable) { table in
                if let venue = session.activeVenue {
                    TableDetailSheet(table: table, reservations: model.reservations, venueID: venue.id)
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private func content(for venue: Venue) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero(venue: venue, topInset: proxy.safeAreaInsets.top)

                    VStack(alignment: .leading, spacing: 22) {
                        quickActions

                        if let errorMessage = model.errorMessage {
                            MPNotice(message: errorMessage, actionTitle: "Tekrar dene") {
                                Task { await model.load(venue: venue) }
                            }
                        } else if model.isLoading && model.reservations.isEmpty {
                            MPLoadingRow(title: "Bugünün akışı yükleniyor")
                                .mpCard()
                        } else {
                            if !attentionReservations.isEmpty {
                                attentionSection(venueID: venue.id)
                            }
                            upcomingSection(venueID: venue.id)
                            if !model.waitlist.isEmpty {
                                waitlistSection
                            }
                            if !loadBuckets.isEmpty {
                                loadSection
                            }
                            if !model.tables.isEmpty {
                                floorSection
                            }
                        }
                    }
                    .padding(.horizontal, MP.gutter)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await model.load(venue: venue) }
            .task(id: venue.id) { await model.load(venue: venue) }
        }
    }

    // MARK: Hero

    private func hero(venue: Venue, topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                MPBrandTile(size: 32)
                Text("MasaPort")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(MP.onHero)
                Spacer()
                VenueMenu(onHero: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(formattedDate.uppercased(with: Locale(identifier: "tr_TR")))
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(MP.onHeroSecondary)
                Text(MPDateFormat.greeting(name: firstName))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(MP.onHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(MP.onHeroSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 0) {
                MPMetric(value: activeReservationCount, label: "Rezervasyon", onHero: true)
                heroDivider
                MPMetric(value: insideCount, label: "İçeride", tone: .positive, onHero: true)
                heroDivider
                MPMetric(value: overdueCount, label: "Geciken", tone: overdueCount > 0 ? .critical : .neutral, onHero: true)
                heroDivider
                NavigationLink {
                    WaitlistView()
                } label: {
                    MPMetric(value: model.waitlist.count, label: "Bekleme", tone: model.waitlist.isEmpty ? .neutral : .attention, onHero: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Bekleme listesini açar")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MP.heroFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .padding(.horizontal, MP.gutter)
        .padding(.top, topInset + 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
                .fill(MP.heroGradient)
                .padding(.top, -600)
        }
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 30)
            .padding(.trailing, 10)
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button {
                showsScanner = true
            } label: {
                MPQuickActionLabel(title: "QR check-in", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.plain)

            Button {
                showsWalkIn = true
            } label: {
                MPQuickActionLabel(title: "Walk-in", systemImage: "person.badge.plus", tone: .positive)
            }
            .buttonStyle(.plain)

            Button {
                navigation.tab = .hostDesk
            } label: {
                MPQuickActionLabel(title: "Host Masası", systemImage: "person.2.fill", badge: overdueCount)
            }
            .buttonStyle(.plain)

            NavigationLink {
                WaitlistView()
            } label: {
                MPQuickActionLabel(title: "Bekleme", systemImage: "hourglass", badge: waitingCount)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Waitlist

    private var waitlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Bekleme listesi", systemImage: "hourglass", detail: "\(waitingCount) bekleyen", tone: .attention)
            VStack(spacing: 0) {
                if let offerErrorMessage = model.offerErrorMessage {
                    MPNotice(message: offerErrorMessage)
                        .padding(12)
                }
                ForEach(Array(visibleWaitlist.enumerated()), id: \.element.id) { index, entry in
                    waitlistRow(entry)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if index < visibleWaitlist.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
                    Divider().padding(.leading, 14)
                    NavigationLink {
                        WaitlistView()
                    } label: {
                        HStack {
                            Text(model.waitlist.count > visibleWaitlist.count ? "\(model.waitlist.count - visibleWaitlist.count) kayıt daha" : "Bekleme listesini aç")
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
            .mpCard(padding: 0)
        }
    }

    private func waitlistRow(_ entry: WaitlistEntry) -> some View {
        let isOffered = entry.status == "OFFERED"
        let isBusy = model.offeringEntryID == entry.id
        return HStack(spacing: 12) {
            MPTimeBlock(time: entry.shortTime, caption: "\(entry.guestCount) kişi", tone: isOffered ? (entry.offerHasExpired ? .critical : .info) : .attention)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.customerName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(entry.waitingText)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if isOffered {
                MPStatusLabel(
                    status: MPStatus(text: entry.offerExpiryText ?? "Teklif gitti", tone: entry.offerHasExpired ? .critical : .info),
                    emphasized: true
                )
            } else {
                Button {
                    offerCandidate = entry
                } label: {
                    HStack(spacing: 5) {
                        if isBusy {
                            ProgressView().controlSize(.mini).tint(MP.onBrand)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Teklif")
                    }
                }
                .buttonStyle(MPCompactButtonStyle(tone: .brand, filled: true))
                .disabled(model.offeringEntryID != nil)
                .accessibilityLabel("\(entry.customerName) için masa teklifi gönder")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !isOffered {
                Button("Teklif gönder", systemImage: "paperplane") { offerCandidate = entry }
            }
            Button("Walk-in'e dönüştür", systemImage: "person.badge.plus") { convertCandidate = entry }
            if let phoneURL = entry.phoneURL {
                Link(destination: phoneURL) { Label("Ara \(entry.customerPhone)", systemImage: "phone") }
            }
        }
    }

    private var visibleWaitlist: [WaitlistEntry] {
        Array(model.waitlist
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == "WAITING" }
                return (lhs.createdAt ?? "") < (rhs.createdAt ?? "")
            }
            .prefix(3))
    }

    // MARK: Load

    private var loadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Gün akışı", systemImage: "chart.bar.fill", detail: peakText)
            VStack(alignment: .leading, spacing: 12) {
                MPHourlyLoad(buckets: loadBuckets, currentHour: currentHour)
                HStack(spacing: 14) {
                    legendDot(MP.brand.opacity(0.3), "Geçti")
                    legendDot(MP.brand, "Şu an")
                    legendDot(MP.brand.opacity(0.62), "Gelecek")
                    Spacer()
                    Text("\(totalExpectedGuests) kişi bekleniyor")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .mpCard()
        }
    }

    // MARK: Floor

    private var floorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Salon durumu", systemImage: "tablecells.fill", detail: "\(emptyTableCount) / \(model.tables.count) boş")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(tableZones, id: \.zone) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.zone)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(.secondaryLabel))
                            Spacer()
                            Text("\(group.tables.count { $0.floorState == .empty }) boş")
                                .font(.caption)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                            ForEach(group.tables) { table in
                                Button {
                                    selectedTable = table
                                } label: {
                                    MPTableChip(table: table)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Masanın rezervasyonlarını gösterir")
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    legendDot(MP.positive, "Dolu")
                    legendDot(MP.attention, "Hesap")
                    legendDot(MP.info, "Temizlik")
                    legendDot(Color(.tertiaryLabel), "Boş")
                }
                .padding(.top, 2)
            }
            .mpCard()
        }
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: Attention

    private func attentionSection(venueID: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Dikkat gerektiren", systemImage: "exclamationmark.circle.fill", detail: "\(attentionReservations.count) kayıt", tone: .critical)
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
                        Divider().padding(.leading, 84)
                    }
                }
                if attentionReservations.count > 4 {
                    Divider().padding(.leading, 14)
                    seeAllButton(title: "Host Masası'nda tümünü gör")
                }
            }
            .mpCard(padding: 0)
        }
    }

    // MARK: Upcoming timeline

    private func upcomingSection(venueID: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: "Sıradaki", systemImage: "clock.fill", detail: upcomingReservations.isEmpty ? nil : "\(upcomingReservations.count) rezervasyon")

            if upcomingReservations.isEmpty {
                MPEmptyState(
                    systemImage: model.reservations.isEmpty ? "calendar.badge.checkmark" : "checkmark.circle",
                    title: model.reservations.isEmpty ? "Bugün için rezervasyon yok" : "Sırada bekleyen rezervasyon yok",
                    message: model.reservations.isEmpty ? "Yeni rezervasyonlar burada görünecek." : "Tüm misafirler karşılandı."
                )
                .mpCard(padding: 0)
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
                                Divider().padding(.leading, 84)
                            }
                        }
                    }
                    if upcomingReservations.count > visibleUpcoming.count {
                        Divider().padding(.leading, 14)
                        seeAllButton(title: "\(upcomingReservations.count - visibleUpcoming.count) rezervasyon daha")
                    }
                }
                .mpCard(padding: 0)
            }
        }
    }

    private func hourHeader(_ hour: String) -> some View {
        HStack(spacing: 8) {
            Text(hour)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(MP.brand)
            Rectangle()
                .fill(MP.hairline)
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

    private var currentHour: Int {
        MPDateFormat.istanbulCalendar.component(.hour, from: referenceDate)
    }

    private var activeReservations: [Reservation] {
        model.reservations.filter { !["CANCELLED", "NO_SHOW"].contains($0.status.uppercased()) }
    }

    private var activeReservationCount: Int { activeReservations.count }

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

    private var waitingCount: Int { model.waitlist.count { $0.status == "WAITING" } }

    private var totalExpectedGuests: Int {
        upcomingReservations.reduce(0) { $0 + $1.guestCount }
    }

    private var emptyTableCount: Int { model.tables.count { $0.floorState == .empty } }

    private var occupiedTableCount: Int { model.tables.count { $0.floorState != .empty } }

    private var summaryLine: String {
        var parts: [String] = []
        if overdueCount > 0 { parts.append("\(overdueCount) geciken misafir") }
        if !upcomingReservations.isEmpty {
            parts.append("\(upcomingReservations.count) rezervasyon bekleniyor")
        }
        if !model.tables.isEmpty {
            parts.append("\(occupiedTableCount) / \(model.tables.count) masa dolu")
        }
        if parts.isEmpty {
            return model.reservations.isEmpty ? "Bugün için henüz rezervasyon yok." : "Servis sakin görünüyor."
        }
        return parts.joined(separator: " · ")
    }

    private var tableZones: [(zone: String, tables: [VenueTable])] {
        var groups: [(zone: String, tables: [VenueTable])] = []
        for table in model.tables {
            let zone = (table.zone ?? "").isEmpty ? "Genel" : table.zone!
            if let index = groups.firstIndex(where: { $0.zone == zone }) {
                groups[index].tables.append(table)
            } else {
                groups.append((zone, [table]))
            }
        }
        return groups
    }

    private var loadBuckets: [MPHourlyLoadBucket] {
        let hours = activeReservations.compactMap { Int($0.startTime.prefix(2)) }
        guard let minHour = hours.min(), let maxHour = hours.max() else { return [] }
        let start = min(minHour, currentHour)
        let end = max(maxHour, currentHour)
        return (start...end).map { hour in
            let matching = activeReservations.filter { Int($0.startTime.prefix(2)) == hour }
            return MPHourlyLoadBucket(
                hour: hour,
                guests: matching.reduce(0) { $0 + $1.guestCount },
                reservations: matching.count
            )
        }
    }

    private var peakText: String? {
        guard let peak = loadBuckets.max(by: { $0.guests < $1.guests }), peak.guests > 0 else { return nil }
        return String(format: "En yoğun %02d:00 · %d kişi", peak.hour, peak.guests)
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

    private var firstName: String? {
        session.user?.name.split(separator: " ").first.map(String.init)
    }

    private var formattedDate: String {
        MPDateFormat.longDay.string(from: Date())
    }
}

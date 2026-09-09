import SwiftUI

struct EventsView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = EventsViewModel()
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
            .navigationTitle("Etkinlikler")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    QRScanButton(isPresented: $showsScanner)
                    VenueMenu()
                }
            }
            .fullScreenCover(isPresented: $showsScanner) {
                CheckinScannerView()
            }
        }
    }

    private func content(for venue: Venue) -> some View {
        List {
            if let errorMessage = model.errorMessage {
                MPNotice(message: errorMessage, actionTitle: "Yenile") {
                    Task { await model.load(venueID: venue.id) }
                }
                .mpPlainRow(vertical: 4)
            }

            if model.isLoading && model.events.isEmpty {
                MPLoadingRow(title: "Etkinlikler yükleniyor")
                    .mpPlainRow()
            } else if model.events.isEmpty && !model.isLoading {
                MPEmptyState(
                    systemImage: "ticket",
                    title: "Henüz etkinlik yok",
                    message: "Etkinlikler web panelinden oluşturulur; burada listelenir ve check-in yapılır."
                )
                .mpCard(padding: 0)
                .mpPlainRow(vertical: 4)
            } else {
                if !model.events.isEmpty {
                    overview
                        .mpPlainRow(vertical: 2)
                }
                ForEach(model.grouped, id: \.phase) { group in
                    Section {
                        ForEach(group.events) { event in
                            NavigationLink {
                                EventDetailView(event: event, venueID: venue.id)
                            } label: {
                                EventRow(event: event, phase: group.phase)
                            }
                        }
                    } header: {
                        MPListSectionHeader(title: group.phase.title, count: group.events.count, tone: group.phase == .live ? .positive : .neutral)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(venueID: venue.id) }
        .task(id: venue.id) { await model.load(venueID: venue.id) }
    }

    private var overview: some View {
        HStack(spacing: 0) {
            MPMetric(value: liveCount, label: "Şu an", tone: liveCount > 0 ? .positive : .neutral)
            MPMetric(value: upcomingCount, label: "Yaklaşan", tone: .neutral)
            MPMetric(value: soldTickets, label: "Satılan bilet", tone: .neutral)
        }
        .mpCard(padding: 14)
    }

    private var liveCount: Int { model.grouped.first { $0.phase == .live }?.events.count ?? 0 }
    private var upcomingCount: Int { model.grouped.first { $0.phase == .upcoming }?.events.count ?? 0 }
    private var soldTickets: Int {
        model.events
            .filter { $0.phase() != .past }
            .reduce(0) { $0 + $1.soldTickets }
    }
}

private struct EventRow: View {
    let event: EventSummary
    let phase: EventPhase

    var body: some View {
        let instance = event.displayedInstance
        let start = instance?.startDatetime ?? event.startDatetime
        HStack(alignment: .center, spacing: 12) {
            MPDateLeaf(
                day: EventDates.dayNumber(start),
                month: EventDates.monthShort(start),
                tone: phase == .live ? .positive : .neutral
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(phase == .past ? Color(.secondaryLabel) : Color(.label))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(EventDates.time(start))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(phase == .live ? MP.positive : Color(.secondaryLabel))
                    Text("·")
                    Text(capacityText)
                    if let sessions = sessionCountText {
                        Text("·")
                        Text(sessions)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
                if let capacity = event.maxCapacity, capacity > 0, phase != .past {
                    MPBar(progress: Double(event.soldTickets) / Double(capacity), tone: fillTone(sold: event.soldTickets, capacity: capacity), height: 4)
                        .frame(maxWidth: 140)
                }
            }

            Spacer(minLength: 4)

            if phase == .live {
                MPPill(text: "Sürüyor", tone: .positive)
            } else if let paymentType = event.paymentType, paymentType.uppercased() != "NONE" {
                Image(systemName: "creditcard")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityLabel("Ödemeli etkinlik")
            }
        }
        .padding(.vertical, 4)
    }

    private func fillTone(sold: Int, capacity: Int) -> MPTone {
        let ratio = Double(sold) / Double(capacity)
        if ratio >= 0.9 { return .attention }
        return .brand
    }

    private var capacityText: String {
        if let capacity = event.maxCapacity, capacity > 0 {
            return "\(event.soldTickets) / \(capacity) bilet"
        }
        return "\(event.soldTickets) bilet"
    }

    private var sessionCountText: String? {
        let upcoming = event.upcomingInstances?.count ?? 0
        guard upcoming > 1 else { return nil }
        return "\(upcoming) seans"
    }
}

extension EventDates {
    static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d"
        return formatter
    }()

    static let monthShortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static func dayNumber(_ value: String?) -> String {
        parse(value).map { dayNumberFormatter.string(from: $0) } ?? "—"
    }

    static func monthShort(_ value: String?) -> String {
        parse(value).map { monthShortFormatter.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? ""
    }
}

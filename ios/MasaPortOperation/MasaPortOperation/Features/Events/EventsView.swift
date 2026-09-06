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
                .mpPlainRow()
            } else {
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
                        HStack(spacing: 6) {
                            if group.phase == .live {
                                Circle().fill(MP.positive).frame(width: 6, height: 6)
                            }
                            Text(group.phase.title)
                            Text(group.events.count, format: .number)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(venueID: venue.id) }
        .task(id: venue.id) { await model.load(venueID: venue.id) }
    }
}

private struct EventRow: View {
    let event: EventSummary
    let phase: EventPhase

    var body: some View {
        let instance = event.displayedInstance
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.map { EventDates.time($0.startDatetime) } ?? EventDates.time(event.startDatetime))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(phase == .live ? MP.positive : Color(.label))
                Text(instance?.dayText ?? EventDates.day(event.startDatetime))
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }
            .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(phase == .past ? Color(.secondaryLabel) : Color(.label))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: "person.2")
                        .font(.caption2)
                    Text(capacityText)
                    if let sessions = sessionCountText {
                        Text("·")
                        Text(sessions)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if phase == .live {
                MPStatusLabel(status: MPStatus(text: "Sürüyor", tone: .positive), emphasized: true)
            } else if let paymentType = event.paymentType, paymentType.uppercased() != "NONE" {
                Image(systemName: "creditcard")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityLabel("Ödemeli etkinlik")
            }
        }
        .padding(.vertical, 4)
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

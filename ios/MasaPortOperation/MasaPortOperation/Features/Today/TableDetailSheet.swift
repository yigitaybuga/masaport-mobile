import SwiftUI

/// Salon durumunda bir masaya dokununca açılır: masanın bugünkü rezervasyonları.
struct TableDetailSheet: View {
    let table: VenueTable
    let reservations: [Reservation]
    let venueID: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let current = currentReservation {
                        section(title: "Şu an masada", systemImage: "person.fill.checkmark", tone: .positive, items: [current])
                    }
                    if !upcoming.isEmpty {
                        section(title: "Bugün gelecek", systemImage: "clock.fill", tone: .neutral, items: upcoming)
                    }
                    if !finished.isEmpty {
                        section(title: "Tamamlanan", systemImage: "checkmark.circle", tone: .neutral, items: finished)
                    }
                    if currentReservation == nil && upcoming.isEmpty && finished.isEmpty {
                        MPEmptyState(
                            systemImage: "tablecells",
                            title: "Bu masaya bugün rezervasyon yok",
                            message: "Walk-in misafirleri Host Masası'ndan bu masaya atayabilirsiniz."
                        )
                        .mpCard(padding: 0)
                    }
                }
                .padding(.horizontal, MP.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(MP.background)
            .navigationTitle("Masa \(table.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        let state = table.floorState
        return HStack(spacing: 14) {
            MPIconTile(systemImage: "tablecells.fill", tone: state.tone, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Masa \(table.name)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                HStack(spacing: 6) {
                    MPTag(text: "\(table.capacity) kişilik", systemImage: "person.2.fill")
                    if let zone = table.zone, !zone.isEmpty {
                        MPTag(text: zone, systemImage: "mappin")
                    }
                }
            }
            Spacer(minLength: 0)
            MPPill(text: state.title, tone: state.tone == .neutral ? .neutral : state.tone)
        }
        .mpCard()
    }

    private func section(title: String, systemImage: String, tone: MPTone, items: [Reservation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MPSectionHeader(title: title, systemImage: systemImage, detail: "\(items.count) kayıt", tone: tone)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, reservation in
                    NavigationLink {
                        ReservationDetailView(reservation: reservation, venueID: venueID)
                    } label: {
                        ReservationRow(reservation: reservation)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 84)
                    }
                }
            }
            .mpCard(padding: 0)
        }
    }

    // MARK: Data

    private var tableReservations: [Reservation] {
        reservations
            .filter { $0.tables.contains { $0.id == table.id } }
            .sorted { ($0.startDate() ?? .distantFuture) < ($1.startDate() ?? .distantFuture) }
    }

    private var currentReservation: Reservation? {
        tableReservations.first {
            if case .inside = $0.operationalState() { return true }
            return false
        }
    }

    private var upcoming: [Reservation] {
        tableReservations.filter {
            switch $0.operationalState() {
            case .now, .upcoming, .later, .overdue, .pending: true
            default: false
            }
        }
    }

    private var finished: [Reservation] {
        tableReservations.filter {
            if case .terminal = $0.operationalState() { return true }
            return false
        }
    }
}

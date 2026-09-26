import SwiftUI

/// Host Masası "Salon" görünümü: masalar bölge bölge, misafirler basılı tutup sürüklenerek taşınır.
/// Sürükleme, List/ScrollView ile çakışmamak için sistem drag&drop yerine uzun basma + DragGesture ile yapılır.
struct HostDeskFloorView: View {
    let tables: [VenueTable]
    let reservations: [Reservation]
    let busyReservationID: Int?
    let onMove: (Reservation, VenueTable) -> Void
    let onOpen: (Reservation) -> Void

    private struct DragState {
        let reservation: Reservation
        var location: CGPoint
    }

    private struct TileFramesKey: PreferenceKey {
        static var defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    private static let space = "host-desk-floor"

    @State private var drag: DragState?
    @State private var tileFrames: [Int: CGRect] = [:]
    @State private var pickupCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            unassignedTray

            ForEach(zones, id: \.zone) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.zone)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(.secondaryLabel))
                        Spacer()
                        Text("\(group.tables.count { occupant(of: $0) == nil }) boş")
                            .font(.caption)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(group.tables) { table in
                            tile(table)
                        }
                    }
                }
            }

            Label("Misafiri basılı tutup bir masaya bırakın. Mevcut masası yeni masayla değiştirilir.", systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
        .overlay(alignment: .topLeading) {
            if let drag {
                dragPreview(drag.reservation)
                    .position(x: drag.location.x, y: drag.location.y - 44)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pickupCount)
        .animation(.snappy(duration: 0.18), value: drag?.reservation.id)
    }

    // MARK: Drag

    private var hoveredTableID: Int? {
        guard let drag else { return nil }
        return tileFrames.first { $0.value.contains(drag.location) }?.key
    }

    private func dragGesture(for reservation: Reservation) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let dragValue):
                    guard let dragValue else {
                        if drag == nil {
                            pickupCount += 1
                        }
                        return
                    }
                    if drag == nil { pickupCount += 1 }
                    drag = DragState(reservation: reservation, location: dragValue.location)
                default:
                    break
                }
            }
            .onEnded { value in
                defer { drag = nil }
                guard case .second(true, let dragValue?) = value else { return }
                let location = dragValue.location
                guard let targetID = tileFrames.first(where: { $0.value.contains(location) })?.key,
                      let table = tables.first(where: { $0.id == targetID }) else { return }
                if reservation.tables.count == 1, reservation.tables.first?.id == table.id { return }
                onMove(reservation, table)
            }
    }

    private func dragPreview(_ reservation: Reservation) -> some View {
        HStack(spacing: 8) {
            MPAvatar(name: reservation.displayName, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(reservation.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text(reservation.guestText)
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(MP.card, in: Capsule())
        .overlay { Capsule().strokeBorder(MP.brand, lineWidth: 1.5) }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    // MARK: Tray

    @ViewBuilder
    private var unassignedTray: some View {
        let waiting = unassignedReservations
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Masa bekleyen", systemImage: "tablecells.badge.ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(waiting.isEmpty ? Color(.secondaryLabel) : MP.attention)
                Spacer()
                Text(waiting.count, format: .number)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            if waiting.isEmpty {
                Text("Bugün masasız rezervasyon yok.")
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(waiting) { reservation in
                            guestChip(reservation)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
        .mpCard(padding: 14)
    }

    private func guestChip(_ reservation: Reservation) -> some View {
        let status = reservation.operationBadge()
        let isDragging = drag?.reservation.id == reservation.id
        return HStack(spacing: 8) {
            MPAvatar(name: reservation.displayName, size: 30, tone: status.tone == .neutral ? .brand : status.tone)
            VStack(alignment: .leading, spacing: 1) {
                Text(reservation.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text("\(reservation.shortTime) · \(reservation.guestText)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Image(systemName: "line.3.horizontal")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(MP.fill, in: Capsule())
        .overlay { Capsule().strokeBorder(isDragging ? MP.brand : MP.hairline, lineWidth: isDragging ? 1.5 : 1) }
        .opacity(busyReservationID == reservation.id || isDragging ? 0.45 : 1)
        .contentShape(Capsule())
        .onTapGesture { onOpen(reservation) }
        .gesture(dragGesture(for: reservation))
        .accessibilityLabel("\(reservation.displayName), \(reservation.shortTime), \(reservation.guestText), masa bekliyor")
        .accessibilityHint("Basılı tutup bir masaya sürükleyerek atayın")
    }

    // MARK: Tiles

    private func tile(_ table: VenueTable) -> some View {
        let occupant = occupant(of: table)
        let state = occupant.map { tone(for: $0) } ?? .neutral
        let isTarget = hoveredTableID == table.id
        let isSource = drag != nil && occupant?.id == drag?.reservation.id
        let tileView = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(table.name)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(state == .neutral ? Color(.label) : state.color)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Image(systemName: "person.fill").font(.system(size: 8))
                    Text(table.capacity, format: .number)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(.tertiaryLabel))
            }
            if let occupant {
                VStack(alignment: .leading, spacing: 1) {
                    Text(occupant.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                    Text(occupantCaption(occupant))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(state == .neutral ? Color(.secondaryLabel) : state.color)
                        .lineLimit(1)
                }
            } else {
                Text(isTarget ? "Buraya bırak" : "Boş")
                    .font(.caption.weight(isTarget ? .semibold : .regular))
                    .foregroundStyle(isTarget ? MP.brand : Color(.tertiaryLabel))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 70)
        .background(
            isTarget ? MP.brand.opacity(0.18) : (state == .neutral ? MP.fill : state.color.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous)
                .strokeBorder(isTarget ? MP.brand : (state == .neutral ? MP.hairline : state.color.opacity(0.35)), lineWidth: isTarget ? 2 : 1)
        }
        .scaleEffect(isTarget ? 1.04 : 1)
        .opacity(isSource || (busyReservationID != nil && busyReservationID == occupant?.id) ? 0.45 : 1)
        .animation(.snappy(duration: 0.18), value: isTarget)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: TileFramesKey.self, value: [table.id: proxy.frame(in: .named(Self.space))])
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: MP.radiusSmall, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Masa \(table.name), \(table.capacity) kişilik, \(occupant.map { "\($0.displayName) \(occupantCaption($0))" } ?? "boş")")

        return Group {
            if let occupant {
                tileView
                    .onTapGesture { onOpen(occupant) }
                    .gesture(dragGesture(for: occupant))
                    .accessibilityHint("Basılı tutup başka masaya sürükleyerek taşıyın")
            } else {
                tileView
            }
        }
    }

    // MARK: Data

    private var activeReservations: [Reservation] {
        reservations.filter { !$0.isTerminal }
    }

    private var unassignedReservations: [Reservation] {
        activeReservations
            .filter { !$0.hasTable && !$0.checkedIn }
            .sorted { ($0.startDate() ?? .distantFuture) < ($1.startDate() ?? .distantFuture) }
    }

    private var zones: [(zone: String, tables: [VenueTable])] {
        var groups: [(zone: String, tables: [VenueTable])] = []
        for table in tables {
            let zone = (table.zone ?? "").isEmpty ? "Genel" : table.zone!
            if let index = groups.firstIndex(where: { $0.zone == zone }) {
                groups[index].tables.append(table)
            } else {
                groups.append((zone, [table]))
            }
        }
        return groups
    }

    /// Masadaki misafir: içerideki öncelikli, yoksa en yakın gelecek rezervasyon.
    private func occupant(of table: VenueTable) -> Reservation? {
        let assigned = activeReservations.filter { $0.tables.contains { $0.id == table.id } }
        if let inside = assigned.first(where: { $0.isInside }) { return inside }
        return assigned
            .filter { !$0.checkedIn }
            .min { ($0.startDate() ?? .distantFuture) < ($1.startDate() ?? .distantFuture) }
    }

    private func tone(for reservation: Reservation) -> MPTone {
        switch reservation.operationalState() {
        case .inside:
            return .positive
        case .overdue: return .critical
        case .now, .upcoming: return .info
        case .pending: return .attention
        default: return .neutral
        }
    }

    private func occupantCaption(_ reservation: Reservation) -> String {
        if reservation.isInside {
            return reservation.serviceStatus?.localizedServiceStatus ?? "İçeride"
        }
        return "\(reservation.shortTime) · \(reservation.guestText)"
    }
}

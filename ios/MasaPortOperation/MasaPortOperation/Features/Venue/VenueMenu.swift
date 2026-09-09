import SwiftUI

/// Gezinme çubuğunda aktif mekanı gösterir; birden fazla mekan varsa geçiş menüsü açar.
struct VenueMenu: View {
    @EnvironmentObject private var session: SessionStore
    var onHero = false

    var body: some View {
        Menu {
            ForEach(session.venues) { venue in
                Button {
                    session.selectVenue(venue)
                } label: {
                    if venue.id == session.activeVenue?.id {
                        Label(venue.name, systemImage: "checkmark")
                    } else {
                        Text(venue.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(onHero ? MP.onHeroSecondary : MP.brand)
                Text(session.activeVenue?.name ?? "Mekan seç")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(onHero ? MP.onHero : Color(.label))
                    .lineLimit(1)
                if session.venues.count > 1 {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(onHero ? MP.onHeroSecondary : Color(.secondaryLabel))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(onHero ? MP.heroFill : MP.fill, in: Capsule())
            .overlay {
                Capsule().strokeBorder(onHero ? Color.white.opacity(0.14) : MP.hairline, lineWidth: 1)
            }
        }
        .disabled(session.venues.count < 2)
        .accessibilityLabel("Aktif mekan, \(session.activeVenue?.name ?? "seçilmedi")")
        .accessibilityHint(session.venues.count > 1 ? "Mekan değiştirmek için çift dokunun" : "")
    }
}

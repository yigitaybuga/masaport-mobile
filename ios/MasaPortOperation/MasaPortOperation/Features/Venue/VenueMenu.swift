import SwiftUI

/// Gezinme çubuğunda aktif mekanı gösterir; birden fazla mekan varsa geçiş menüsü açar.
struct VenueMenu: View {
    @EnvironmentObject private var session: SessionStore

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
            HStack(spacing: 5) {
                Text(session.activeVenue?.name ?? "Mekan seç")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                if session.venues.count > 1 {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(MP.fill, in: Capsule())
        }
        .disabled(session.venues.count < 2)
        .accessibilityLabel("Aktif mekan, \(session.activeVenue?.name ?? "seçilmedi")")
        .accessibilityHint(session.venues.count > 1 ? "Mekan değiştirmek için çift dokunun" : "")
    }
}

import SwiftUI

/// Dikey listede etkinlik kartı.
struct EventCard: View {
    let event: PublicEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MPRemoteImage(url: .media(event.imageUrl), placeholderSymbol: "ticket", role: .card)
                .frame(width: 104, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(Format.eventDate(event.startDate))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MP.warm)
                    .textCase(.uppercase)
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.placeLine)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    EventPriceLabel(event: event)
                    if let badge = event.nextInstance?.availabilityBadge {
                        MPPill(text: badge.text, tone: badge.tone)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 128)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Yatay kaydırmalı etkinlik kartı (Keşfet).
struct EventTile: View {
    let event: PublicEvent
    var width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPRemoteImage(url: .media(event.imageUrl), placeholderSymbol: "ticket", role: .card)
                .frame(width: width, height: width * 1.15)
                .clipShape(RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    MPGlassBadge(text: Format.eventDate(event.startDate), systemImage: "calendar")
                        .padding(10)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.placeLine)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                EventPriceLabel(event: event)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct EventPriceLabel: View {
    let event: PublicEvent

    var body: some View {
        if let price = Format.price(event.pricePerPerson?.value) {
            Text(price)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        } else if event.ticketUrl != nil {
            Text("Bilet sitesinde")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
        } else {
            Text("Ücretsiz")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MP.positive)
        }
    }
}

extension PublicEvent {
    var placeLine: String {
        let place = venue?.name ?? location?.name
        let area = location?.district?.name ?? location?.city?.name
        return [place, area].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
    }

    var favoriteItem: FavoritesStore.Item {
        FavoritesStore.Item(kind: .event, remoteId: id, title: title, subtitle: placeLine, image: imageUrl, slug: slug, addedAt: .now)
    }
}

extension EventInstance {
    var availabilityBadge: (text: String, tone: MPTone)? {
        guard maxCapacity != nil else { return nil }
        if isSoldOut { return ("Dolu", .critical) }
        if isLowStock { return ("Son \(availableSpots ?? 0) yer", .attention) }
        return ("Yer var", .positive)
    }
}

extension DiscoveryCard {
    /// Feed etkinlik kartını liste modeline dönüştürür.
    var asPublicEvent: PublicEvent {
        PublicEvent(
            id: id, slug: slug, title: title ?? name ?? "", description: description, imageUrl: displayImage,
            pricePerPerson: pricePerPerson, paymentType: nil, isRecurring: nil, startDatetime: startDatetime, endDatetime: nil,
            maxCapacity: nil, category: category,
            location: EventLocation(mode: nil, name: venueName, address: nil, neighborhood: nil, city: city, district: district, latitude: nil, longitude: nil),
            ticketUrl: ticketUrl, venue: nil, nextInstance: nil
        )
    }
}

extension EventDetail {
    var placeLine: String {
        let place = venue?.name ?? location?.name
        let area = location?.district?.name ?? location?.city?.name
        return [place, area].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
    }

    var favoriteItem: FavoritesStore.Item {
        FavoritesStore.Item(kind: .event, remoteId: id, title: title, subtitle: placeLine, image: imageUrl, slug: slug, addedAt: .now)
    }
}

import SwiftUI

/// Dikey listede tam genişlik restoran kartı.
struct RestaurantCard: View {
    let listing: ListingCard
    var onTime: ((String) -> Void)? = nil

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                MPRemoteImage(url: .media(listing.image), role: .card)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: MP.cardRadius, style: .continuous))

                HStack {
                    if let distance = Format.distance(listing.distance) {
                        MPGlassBadge(text: distance, systemImage: "location.fill")
                    }
                    Spacer()
                    FavoriteButton(item: listing.favoriteItem)
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(listing.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    MPRatingLabel(rating: listing.rating?.value)
                }
                Text(listing.summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)

                if let times = listing.discoveryAvailableTimes, !times.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(times, id: \.self) { time in
                                MPTimeChip(time: time.shortTime, isSelected: time == listing.discoveryMatchedTime) {
                                    onTime?(time)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.top, 4)
                } else if listing.isReservationActive == false {
                    MPPill(text: "Rezervasyon kapalı", tone: .neutral)
                        .padding(.top, 2)
                } else if let booked = listing.bookedTodayCount, booked > 0 {
                    MPPill(text: "Bugün \(booked) rezervasyon", tone: .warm, systemImage: "flame.fill")
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Yatay kaydırmalı kompakt restoran kartı (Keşfet).
struct RestaurantTile: View {
    let listing: ListingCard
    var width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MPRemoteImage(url: .media(listing.image), role: .card)
                .frame(width: width, height: width * 0.68)
                .clipShape(RoundedRectangle(cornerRadius: MP.radius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let rating = Format.rating(listing.rating?.value) {
                        MPGlassBadge(text: rating, systemImage: "star.fill")
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(listing.summaryLine)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
                if let times = listing.discoveryAvailableTimes, !times.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(times.prefix(3), id: \.self) { time in
                            Text(time.shortTime)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundStyle(MP.brand)
                                .background(MP.brand.opacity(0.10), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Discovery feed'den gelen restoran kartı (müsaitlik verisi olmadan).
struct DiscoveryRestaurantTile: View {
    let card: DiscoveryCard
    var hydrated: ListingCard? = nil
    var width: CGFloat = 220

    var body: some View {
        if let hydrated {
            RestaurantTile(listing: hydrated, width: width)
        } else {
            RestaurantTile(listing: card.asListingCard, width: width)
        }
    }
}

struct FavoriteButton: View {
    let item: FavoritesStore.Item
    @Environment(AppModel.self) private var model

    private var isFavorite: Bool {
        item.kind == .listing ? model.favorites.isFavorite(listing: item.remoteId) : model.favorites.isFavorite(event: item.remoteId)
    }

    var body: some View {
        Button {
            withAnimation(.bouncy) { model.favorites.toggle(item) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isFavorite ? MP.critical : Color.primary)
                .frame(width: 34, height: 34)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .accessibilityLabel(isFavorite ? "Favorilerden çıkar" : "Favorilere ekle")
    }
}

extension ListingCard {
    var summaryLine: String {
        var parts: [String] = []
        if let cuisine, !cuisine.isEmpty { parts.append(cuisine.prefix(2).joined(separator: ", ")) }
        if let place = neighborhood?.nilIfBlank ?? district?.name ?? location?.nilIfBlank ?? city?.name { parts.append(place) }
        if let priceRange = priceRange?.nilIfBlank { parts.append(priceRange) }
        return parts.joined(separator: " · ")
    }

    var favoriteItem: FavoritesStore.Item {
        FavoritesStore.Item(kind: .listing, remoteId: id, title: name, subtitle: summaryLine, image: image, slug: slug, addedAt: .now)
    }
}

extension ListingDetail {
    var summaryLine: String {
        var parts: [String] = []
        if let cuisine, !cuisine.isEmpty { parts.append(cuisine.prefix(3).joined(separator: ", ")) }
        if let place = neighborhood?.nilIfBlank ?? district?.name ?? location?.nilIfBlank ?? city?.name { parts.append(place) }
        if let priceRange = priceRange?.nilIfBlank { parts.append(priceRange) }
        return parts.joined(separator: " · ")
    }

    var favoriteItem: FavoritesStore.Item {
        FavoritesStore.Item(kind: .listing, remoteId: id, title: name, subtitle: summaryLine, image: coverImage ?? heroImage, slug: slug, addedAt: .now)
    }
}

extension DiscoveryCard {
    var asListingCard: ListingCard {
        ListingCard(
            id: id, name: name ?? title ?? "", slug: slug ?? "", cuisine: cuisine, location: location, neighborhood: nil,
            city: city, district: district, rating: rating, priceRange: priceRange, description: description, image: displayImage,
            features: nil, venue: nil, latitude: nil, longitude: nil, distance: nil, sectors: nil, bookedTodayCount: nil,
            discoveryMatchedTime: nil, discoveryAvailableTimes: nil, isReservationActive: nil
        )
    }
}

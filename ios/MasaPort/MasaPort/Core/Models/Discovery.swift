import Foundation

/// Discovery feed kartları modül düzenine göre farklı alanlar taşır; hepsi opsiyonel tutulur.
struct DiscoveryCard: Codable, Hashable, Identifiable {
    let id: Int
    // Koleksiyon / içerik kartı
    let title: String?
    let description: String?
    let image: String?
    let href: String?
    let listingIds: [Int]?
    // Restoran kartı
    let name: String?
    let slug: String?
    let cuisine: [String]?
    let location: String?
    let rating: APINumber?
    let priceRange: String?
    let city: CityRef?
    // Etkinlik kartı
    let imageUrl: String?
    let pricePerPerson: APINumber?
    let ticketUrl: String?
    let startDatetime: String?
    let venueName: String?
    let district: DistrictRef?
    let category: EventCategory?
    let isTonight: Bool?
    let isWeekend: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, description, image, href, name, slug, cuisine, location, rating, priceRange, city, district, category
        case listingIds = "listing_ids"
        case imageUrl = "image_url"
        case pricePerPerson = "price_per_person"
        case ticketUrl = "ticket_url"
        case startDatetime = "start_datetime"
        case venueName = "venue_name"
        case isTonight = "is_tonight"
        case isWeekend = "is_weekend"
    }

    var displayTitle: String { title ?? name ?? "" }
    var displayImage: String? { image ?? imageUrl }

    /// `/search?cuisine=...` veya `/search?listingIds=...` biçimindeki `href` alanını liste filtresine çevirir.
    var hrefQueryItems: [URLQueryItem] {
        guard let href, let components = URLComponents(string: href) else { return [] }
        return components.queryItems ?? []
    }

    var resolvedListingIds: [Int] {
        if let listingIds, !listingIds.isEmpty { return listingIds }
        return hrefQueryItems.first { $0.name == "listingIds" || $0.name == "ids" }?.value?
            .split(separator: ",").compactMap { Int($0) } ?? []
    }

    var resolvedCuisine: String? {
        hrefQueryItems.first { $0.name == "cuisine" }?.value?.nilIfBlank
    }
}

struct DiscoveryModule: Codable, Hashable, Identifiable {
    let key: String
    let title: String?
    let subtitle: String?
    let description: String?
    let ctaLabel: String?
    let ctaHref: String?
    let layout: String?
    let selectionReason: String?
    let pinned: [DiscoveryCard]?
    let candidates: [DiscoveryCard]?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, title, subtitle, description, layout, pinned, candidates
        case ctaLabel = "cta_label"
        case ctaHref = "cta_href"
        case selectionReason = "selection_reason"
    }

    /// Sunucu aday havuzu döndürür; istemci rotasyon kovasına göre deterministik seçer.
    func rotatedCards(seed: Int, limit: Int) -> [DiscoveryCard] {
        let pinnedCards = pinned ?? []
        var pool = (candidates ?? []).filter { candidate in !pinnedCards.contains { $0.id == candidate.id } }
        guard !pool.isEmpty else { return Array(pinnedCards.prefix(limit)) }
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &+ key.hashValue))
        pool.shuffle(using: &generator)
        return Array((pinnedCards + pool).prefix(limit))
    }
}

struct DiscoveryFeed: Codable {
    let surface: String
    let cityId: Int?
    let rotationBucket: Int?
    let modules: [DiscoveryModule]

    enum CodingKeys: String, CodingKey {
        case surface, modules
        case cityId = "city_id"
        case rotationBucket = "rotation_bucket"
    }

    func module(_ key: String) -> DiscoveryModule? {
        modules.first { $0.key == key }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

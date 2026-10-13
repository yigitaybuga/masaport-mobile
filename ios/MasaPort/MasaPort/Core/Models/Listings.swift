import Foundation

struct Sector: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let emoji: String?
    let iconUrl: String?
}

struct ListingVenue: Codable, Hashable {
    let id: Int
    let name: String?
    let logo: String?
    let timezone: String?
    let defaultReservationDurationMinutes: Int?
    let phone: String?
    let address: String?
    let email: String?
    let latitude: APINumber?
    let longitude: APINumber?
}

/// `/public/listings` kartı.
struct ListingCard: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String
    let cuisine: [String]?
    let location: String?
    let neighborhood: String?
    let city: CityRef?
    let district: DistrictRef?
    let rating: APINumber?
    let priceRange: String?
    let description: String?
    let image: String?
    let features: [String]?
    let venue: ListingVenue?
    let latitude: APINumber?
    let longitude: APINumber?
    let distance: Double?
    let sectors: [Sector]?
    let bookedTodayCount: Int?
    let discoveryMatchedTime: String?
    let discoveryAvailableTimes: [String]?
    let isReservationActive: Bool?
}

struct Pagination: Codable, Hashable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

struct ListingsPage: Codable {
    let listings: [ListingCard]
    let pagination: Pagination?
}

struct ListingFilters: Codable, Hashable {
    let defaultDate: String?
    let defaultTime: String?
    let defaultGuestCount: Int?
    let locations: [String]?
    let timeOptions: [String]?
    let guestCountOptions: [Int]?
    let maxGuestCapacity: Int?
    let totalListings: Int?

    enum CodingKeys: String, CodingKey {
        case defaultDate = "default_date"
        case defaultTime = "default_time"
        case defaultGuestCount = "default_guest_count"
        case locations
        case timeOptions = "time_options"
        case guestCountOptions = "guest_count_options"
        case maxGuestCapacity = "max_guest_capacity"
        case totalListings = "total_listings"
    }
}

struct WorkingDay: Codable, Hashable {
    let open: String?
    let close: String?
    let closed: Bool?
}

struct ListingReview: Codable, Hashable, Identifiable {
    let id: Int
    let userName: String?
    let rating: APINumber?
    let comment: String?
    let date: String?
    /// Rezervasyonla gerçekleşmiş ziyarete bağlı yorum.
    var verified: Bool? = nil
    var photos: [String]? = nil
    var ownerReply: OwnerReply? = nil

    struct OwnerReply: Codable, Hashable {
        let text: String
        let date: String?
    }
}

struct ReviewStats: Codable, Hashable {
    let averageRating: APINumber?
    let totalReviews: Int?
    let ratingDistribution: [String: Int]?
    var subRatings: SubRatings? = nil
    var noiseLabel: String? = nil

    struct SubRatings: Codable, Hashable {
        let foodRating: APINumber?
        let serviceRating: APINumber?
        let ambienceRating: APINumber?
        let valueRating: APINumber?

        var rows: [(label: String, value: Double)] {
            [("Yemek", foodRating), ("Servis", serviceRating), ("Ambiyans", ambienceRating), ("Fiyat/performans", valueRating)]
                .compactMap { label, number in number?.value.map { (label, $0) } }
        }
    }
}

/// `/public/restaurants/:slug` detayı.
struct ListingDetail: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String
    let cuisine: [String]?
    let location: String?
    let neighborhood: String?
    let city: CityRef?
    let district: DistrictRef?
    let latitude: APINumber?
    let longitude: APINumber?
    let rating: APINumber?
    let priceRange: String?
    let description: String?
    let coverImage: String?
    let heroImage: String?
    let gallery: [String]?
    let contactPhone: String?
    let contactEmail: String?
    let contactAddress: String?
    let workingHours: [String: WorkingDay]?
    let features: [String]?
    let venue: ListingVenue?
    let isReservationActive: Bool?
    let sectors: [Sector]?
    let bookedTodayCount: Int?
    let reviews: [ListingReview]?
    let reviewStats: ReviewStats?
    /// Yayındaki QR menü özeti; tam menü `AppConfiguration.menuURL(slug:)` ile açılır.
    let menu: MenuPreview?

    struct MenuPreview: Codable, Hashable {
        let slug: String
        let totalItems: Int?
    }

    /// Detay uç noktası `listing` ve `restaurant` altında aynı nesneyi döndürür.
    struct Response: Codable {
        let listing: ListingDetail?
        let restaurant: ListingDetail?
        var value: ListingDetail? { listing ?? restaurant }
    }
}

import Foundation

struct EventCategory: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String?
}

struct EventLocation: Codable, Hashable {
    let mode: String?
    let name: String?
    let address: String?
    let neighborhood: String?
    let city: CityRef?
    let district: DistrictRef?
    let latitude: APINumber?
    let longitude: APINumber?
}

struct EventVenueRef: Codable, Hashable {
    let id: Int
    let name: String?
    let address: String?
    let logo: String?
    let phone: String?
}

struct EventInstance: Codable, Hashable, Identifiable {
    let id: Int
    let startDatetime: String
    let endDatetime: String?
    let maxCapacity: Int?
    let totalReserved: Int?
    let availableSpots: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
        case maxCapacity = "max_capacity"
        case totalReserved = "total_reserved"
        case availableSpots = "available_spots"
    }

    var startDate: Date? { ISO8601Parser.date(from: startDatetime) }
    var endDate: Date? { endDatetime.flatMap(ISO8601Parser.date(from:)) }

    var isSoldOut: Bool { maxCapacity != nil && (availableSpots ?? 0) <= 0 }
    var isLowStock: Bool { maxCapacity != nil && !isSoldOut && (availableSpots ?? 0) <= 10 }
    var isPast: Bool { (startDate ?? .distantFuture) < .now }
}

/// `/public/events` listesi.
struct PublicEvent: Codable, Hashable, Identifiable {
    let id: Int
    let slug: String?
    let title: String
    let description: String?
    let imageUrl: String?
    let pricePerPerson: APINumber?
    let paymentType: String?
    let isRecurring: Bool?
    let startDatetime: String?
    let endDatetime: String?
    let maxCapacity: Int?
    let category: EventCategory?
    let location: EventLocation?
    let ticketUrl: String?
    let venue: EventVenueRef?
    let nextInstance: EventInstance?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, category, location, venue
        case imageUrl = "image_url"
        case pricePerPerson = "price_per_person"
        case paymentType = "payment_type"
        case isRecurring = "is_recurring"
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
        case maxCapacity = "max_capacity"
        case ticketUrl = "ticket_url"
        case nextInstance = "next_instance"
    }

    var startDate: Date? {
        nextInstance?.startDate ?? startDatetime.flatMap(ISO8601Parser.date(from:))
    }
}

struct EventsPagination: Codable, Hashable {
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page, total
        case perPage = "per_page"
        case totalPages = "total_pages"
    }
}

struct EventsPage: Codable {
    let events: [PublicEvent]
    let pagination: EventsPagination?
}

/// `/events/:id/public` detayı. Prisma satırı camelCase, türetilen alanlar snake_case gelir.
struct EventDetail: Codable, Hashable, Identifiable {
    let id: Int
    let slug: String?
    let title: String
    let description: String?
    let imageUrl: String?
    let pricePerPerson: APINumber?
    let paymentType: String?
    let isRecurring: Bool?
    let startDatetime: String?
    let endDatetime: String?
    let maxCapacity: Int?
    let isPublishedToPublic: Bool?
    let category: EventCategory?
    let venue: EventVenueRef?
    let location: EventLocation?
    let ticketUrl: String?
    let instances: [EventInstance]?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, imageUrl, pricePerPerson, paymentType, isRecurring, startDatetime, endDatetime, maxCapacity, isPublishedToPublic, category, venue, location, instances
        case ticketUrl = "ticket_url"
    }

    var price: Double? { pricePerPerson?.value }
    var isFree: Bool { (paymentType ?? "NONE") == "NONE" || (price ?? 0) <= 0 }
    var upcomingInstances: [EventInstance] { (instances ?? []).filter { !$0.isPast } }
}

enum ISO8601Parser {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }
}

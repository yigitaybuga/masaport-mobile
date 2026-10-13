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
    /// Yalnızca detayda ve bilet seçeneği tanımlı etkinliklerde dolu gelir.
    var ticketAvailability: [EventTicketAvailability]? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
        case maxCapacity = "max_capacity"
        case totalReserved = "total_reserved"
        case availableSpots = "available_spots"
        case ticketAvailability = "ticket_availability"
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
    /// Bölüm ve bilet seçenekleri; tanımlıysa sunucu kayıtta `ticket_option_id` ister.
    var ticketConfig: EventTicketConfig? = nil

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, imageUrl, pricePerPerson, paymentType, isRecurring, startDatetime, endDatetime, maxCapacity, isPublishedToPublic, category, venue, location, instances, ticketConfig
        case ticketUrl = "ticket_url"
    }

    /// Bilet seçenekli etkinlikte sunucu en düşük satıştaki fiyatı (başlangıç fiyatı) gönderir.
    var price: Double? { pricePerPerson?.value }
    var upcomingInstances: [EventInstance] { (instances ?? []).filter { !$0.isPast } }

    /// Deneme hesabındaki mekânlarda sunucu ödeme türünü `NONE` olarak döner.
    var collectsPayment: Bool { (paymentType ?? "NONE") != "NONE" }

    /// Bilet seçeneği tanımlıysa (satışa kapalı olsalar bile) kayıt seçenek olmadan alınmaz.
    var requiresTicketOption: Bool { !(ticketConfig?.options ?? []).isEmpty }

    /// Satışa açık seçenekler; kapalı olanlar hiç gösterilmez.
    var saleableTicketOptions: [EventTicketChoice] { ticketChoices(for: nil) }

    /// Seçilebilecek tüm biletler ücretsizse (veya etkinlik ödeme almıyorsa) ücretsiz sayılır.
    var isFree: Bool {
        guard collectsPayment else { return true }
        if requiresTicketOption { return saleableTicketOptions.allSatisfy(\.isFree) }
        return (price ?? 0) <= 0
    }

    /// Uygulama içinde ödeme gerekmeden kayıt olunabilecek en az bir bilet var mı.
    var offersFreeTicket: Bool {
        requiresTicketOption ? saleableTicketOptions.contains(where: \.isFree) : isFree
    }

    /// Ücretli biletlerin en düşüğü; "₺450 ve üzeri" gibi gösterimler için.
    var lowestPaidPrice: Double? {
        guard collectsPayment else { return nil }
        if requiresTicketOption { return saleableTicketOptions.map(\.unitPrice).filter { $0 > 0 }.min() }
        return (price ?? 0) > 0 ? price : nil
    }

    var hasMultiplePaidPrices: Bool {
        Set(saleableTicketOptions.map(\.unitPrice).filter { $0 > 0 }).count > 1
    }

    /// Seans için seçilebilecek biletler ve kalan kontenjanları. `instance` verilmezse stok bilgisi boş kalır.
    func ticketChoices(for instance: EventInstance?) -> [EventTicketChoice] {
        let config = ticketConfig
        let sections = config?.sections ?? []
        return (config?.options ?? []).filter { $0.active == true }.map { option in
            let stock = instance?.ticketAvailability?.first { $0.optionId == option.id }
            // Eski API seans bazında bilet stoğu göndermez; etkinlik kapasitesi tek sınırdır.
            let fallback = instance.flatMap { $0.maxCapacity == nil ? nil : max(0, $0.availableSpots ?? 0) }
            return EventTicketChoice(
                id: option.id,
                title: option.ticketType?.nilIfBlank ?? "Bilet",
                category: option.category?.nilIfBlank,
                sectionName: sections.first { $0.id == option.sectionId }?.name?.nilIfBlank,
                unitPrice: collectsPayment ? max(0, option.price?.value ?? 0) : 0,
                available: instance?.ticketAvailability == nil ? fallback : stock?.available
            )
        }
    }

    /// Seans kapasitesi dolduysa veya satıştaki tüm biletler tükendiyse seans seçilemez.
    func isSoldOut(_ instance: EventInstance) -> Bool {
        if instance.isSoldOut { return true }
        guard requiresTicketOption else { return false }
        return ticketChoices(for: instance).allSatisfy(\.isSoldOut)
    }
}

/// `ticketConfig`: Prisma JSON alanı olduğu gibi (camelCase) gelir.
struct EventTicketConfig: Codable, Hashable {
    struct Section: Codable, Hashable, Identifiable {
        let id: String
        let name: String?
        let capacity: Int?
    }

    struct Option: Codable, Hashable, Identifiable {
        let id: String
        let ticketType: String?
        let category: String?
        let sectionId: String?
        let price: APINumber?
        let capacity: Int?
        let active: Bool?
    }

    let sections: [Section]?
    let options: [Option]?
}

/// Seans bazında bilet stoğu (`ticket_availability`): `available` nil ise sınırsız, satışa kapalıysa 0.
struct EventTicketAvailability: Codable, Hashable {
    let optionId: String
    let available: Int?
}

/// Kayıt ekranında gösterilen bilet seçeneği.
struct EventTicketChoice: Hashable, Identifiable {
    let id: String
    let title: String
    let category: String?
    let sectionName: String?
    /// Kişi başı fiyat; etkinlik ödeme almıyorsa 0.
    let unitPrice: Double
    /// Kalan kontenjan; nil ise sınırsız.
    let available: Int?

    var isFree: Bool { unitPrice <= 0 }
    var isSoldOut: Bool { available.map { $0 <= 0 } ?? false }
    var isLowStock: Bool { available.map { $0 > 0 && $0 <= 10 } ?? false }
    var detail: String? {
        let parts = [category, sectionName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
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

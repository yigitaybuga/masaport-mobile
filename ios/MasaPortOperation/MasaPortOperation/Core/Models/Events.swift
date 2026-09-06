import Foundation

struct EventInstanceSummary: Codable, Identifiable, Hashable {
    let id: Int
    let eventId: Int
    let startDatetime: String
    let endDatetime: String
    let soldTickets: Int?
}

struct EventSummary: Codable, Identifiable, Hashable {
    let id: Int
    let venueId: Int?
    let title: String
    let description: String?
    let imageUrl: String?
    let startDatetime: String
    let endDatetime: String
    let maxCapacity: Int?
    let paymentType: String?
    let isPublishedToPublic: Bool?
    let activeInstance: EventInstanceSummary?
    let upcomingInstances: [EventInstanceSummary]?
    let pastInstances: [EventInstanceSummary]?
}

struct EventGuest: Codable, Identifiable, Hashable {
    let id: Int
    let fullName: String
}

struct EventReservation: Codable, Identifiable, Hashable {
    let id: Int
    let uuid: String?
    let eventInstanceId: Int?
    let contactName: String
    let contactEmail: String?
    let contactPhone: String?
    let note: String?
    let guestCount: Int
    let paymentStatus: String?
    let totalAmount: FlexibleDecimal?
    let checkedIn: Bool?
    let checkedInAt: String?
    let createdAt: String?
    let eventGuests: [EventGuest]?
    let eventInstance: EventReservationInstance?

    var isCheckedIn: Bool { checkedIn ?? false }
    var isPaid: Bool { (paymentStatus ?? "").uppercased() == "PAID" }
    var displayName: String { contactName.isEmpty ? "Misafir" : contactName }
}

struct EventReservationInstance: Codable, Hashable {
    let id: Int
    let startDatetime: String
    let endDatetime: String
}

/// Prisma Decimal alanları JSON'da bazen sayı bazen metin gelir.
struct FlexibleDecimal: Codable, Hashable {
    let value: Double?

    init(value: Double?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }
}

enum EventDates {
    static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let iso = ISO8601DateFormatter()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "d MMM EEE"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFractional.date(from: value) ?? iso.date(from: value)
    }

    static func day(_ value: String?) -> String {
        parse(value).map { dayFormatter.string(from: $0) } ?? "—"
    }

    static func time(_ value: String?) -> String {
        parse(value).map { timeFormatter.string(from: $0) } ?? "—"
    }
}

extension EventInstanceSummary {
    var startDate: Date? { EventDates.parse(startDatetime) }
    var endDate: Date? { EventDates.parse(endDatetime) }
    var dayText: String { EventDates.day(startDatetime) }
    var timeRangeText: String { "\(EventDates.time(startDatetime))–\(EventDates.time(endDatetime))" }
}

enum EventPhase: Int, Comparable {
    case live, upcoming, past

    static func < (lhs: EventPhase, rhs: EventPhase) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .live: "Şu an"
        case .upcoming: "Yaklaşan"
        case .past: "Geçmiş"
        }
    }
}

extension EventSummary {
    var allInstances: [EventInstanceSummary] {
        var instances: [EventInstanceSummary] = []
        if let activeInstance { instances.append(activeInstance) }
        instances.append(contentsOf: upcomingInstances ?? [])
        instances.append(contentsOf: (pastInstances ?? []))
        return instances.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Kartta gösterilecek seans: süren, yoksa en yakın gelecek, yoksa en son geçmiş.
    var displayedInstance: EventInstanceSummary? {
        activeInstance
            ?? upcomingInstances?.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            ?? pastInstances?.max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    func phase(relativeTo now: Date = .now) -> EventPhase {
        if activeInstance != nil { return .live }
        if let upcoming = upcomingInstances, !upcoming.isEmpty { return .upcoming }
        if let pastInstances, !pastInstances.isEmpty { return .past }
        if let end = EventDates.parse(endDatetime), end >= now { return .upcoming }
        return .past
    }

    var soldTickets: Int { displayedInstance?.soldTickets ?? 0 }
}

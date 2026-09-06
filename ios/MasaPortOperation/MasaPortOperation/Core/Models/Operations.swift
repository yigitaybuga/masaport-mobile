import Foundation

struct Reservation: Codable, Identifiable, Hashable {
    let id: Int
    let uuid: String
    let reservationDate: String
    let startTime: String
    let endTime: String
    let guestCount: Int
    let status: String
    let serviceStatus: String?
    let customerName: String
    let customerPhone: String
    let note: String?
    let tables: [VenueTable]
    let checkedIn: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, uuid, status, note, tables, checkedIn, updatedAt
        case reservationDate
        case startTime
        case endTime
        case guestCount
        case serviceStatus
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
    }
}

struct VenueTable: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let capacity: Int
    let zone: String?
    let serviceStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, name, capacity, zone
        case serviceStatus
    }
}

struct WaitlistEntry: Codable, Identifiable, Hashable {
    let id: Int
    let venueID: Int?
    let timeSlotID: Int?
    let reservationDate: String
    let guestCount: Int
    let customerName: String
    let customerPhone: String
    let customerEmail: String?
    let status: String
    let source: String?
    let note: String?
    let createdAt: String?
    let offerExpiresAt: String?
    let timeSlot: WaitlistTimeSlot?

    enum CodingKeys: String, CodingKey {
        case id, status, source, note
        case venueID = "venue_id"
        case timeSlotID = "time_slot_id"
        case reservationDate = "reservation_date"
        case guestCount = "guest_count"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case customerEmail = "customer_email"
        case createdAt = "created_at"
        case offerExpiresAt = "offer_expires_at"
        case timeSlot = "time_slot"
    }
}

struct WaitlistTimeSlot: Codable, Hashable {
    let id: Int
    let startTime: String
    let endTime: String
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMinutes = "duration_minutes"
    }
}

enum ReservationOperationalState: Equatable {
    case inside
    case overdue(minutes: Int)
    case now
    case upcoming(minutes: Int)
    case pending
    case later
    case terminal

    var sortRank: Int {
        switch self {
        case .inside: 0
        case .overdue: 1
        case .now: 2
        case .upcoming: 3
        case .pending: 4
        case .later: 5
        case .terminal: 6
        }
    }
}

struct AssignableTable: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let capacity: Int
    let zone: String?
    let isAvailable: Bool
    let isCurrent: Bool
    let isRecommended: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, capacity, zone
        case isAvailable = "is_available"
        case isCurrent = "is_current"
        case isRecommended = "is_recommended"
    }
}

struct ReservationTableAvailability: Codable {
    let tables: [AssignableTable]
}

struct ReservationTableUpdate: Codable, Hashable {
    let id: Int
    let name: String?
    let capacity: Int
}

struct ReservationTableAssignment: Codable {
    let tables: [ReservationTableUpdate]
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case tables
        case updatedAt = "updated_at"
    }
}

struct ReservationServiceStatusUpdate: Codable {
    let serviceStatus: String
    let status: String
    let checkedIn: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case serviceStatus = "service_status"
        case checkedIn = "checked_in"
        case updatedAt = "updated_at"
    }
}

extension Reservation {
    func startDate(timeZone: TimeZone = TimeZone(identifier: "Europe/Istanbul")!) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let normalizedTime = startTime.count == 5 ? "\(startTime):00" : String(startTime.prefix(8))
        return formatter.date(from: "\(reservationDate) \(normalizedTime)")
    }

    func minutesUntilStart(
        relativeTo referenceDate: Date = Date(),
        timeZone: TimeZone = TimeZone(identifier: "Europe/Istanbul")!
    ) -> Int? {
        guard let start = startDate(timeZone: timeZone) else { return nil }
        return Int(start.timeIntervalSince(referenceDate) / 60)
    }

    func operationalState(relativeTo referenceDate: Date = Date()) -> ReservationOperationalState {
        let normalizedStatus = status.uppercased()
        let normalizedService = serviceStatus?.uppercased()
        if checkedIn && !["LEFT", "EMPTY"].contains(normalizedService ?? "") {
            return .inside
        }
        if ["COMPLETED", "CANCELLED", "NO_SHOW"].contains(normalizedStatus) {
            return .terminal
        }
        if normalizedStatus == "PENDING" {
            return .pending
        }
        guard let minutes = minutesUntilStart(relativeTo: referenceDate) else {
            return .later
        }
        if minutes < -15 {
            return .overdue(minutes: abs(minutes))
        }
        if minutes <= 5 {
            return .now
        }
        if minutes <= 120 {
            return .upcoming(minutes: minutes)
        }
        return .later
    }

    func updatingTables(_ updatedTables: [ReservationTableUpdate], updatedAt: String) -> Reservation {
        Reservation(
            id: id,
            uuid: uuid,
            reservationDate: reservationDate,
            startTime: startTime,
            endTime: endTime,
            guestCount: guestCount,
            status: status,
            serviceStatus: serviceStatus,
            customerName: customerName,
            customerPhone: customerPhone,
            note: note,
            tables: updatedTables.map { VenueTable(id: $0.id, name: $0.name ?? "Masa", capacity: $0.capacity, zone: nil, serviceStatus: nil) },
            checkedIn: checkedIn,
            updatedAt: updatedAt
        )
    }

    func updatingServiceStatus(_ update: ReservationServiceStatusUpdate) -> Reservation {
        Reservation(
            id: id,
            uuid: uuid,
            reservationDate: reservationDate,
            startTime: startTime,
            endTime: endTime,
            guestCount: guestCount,
            status: update.status,
            serviceStatus: update.serviceStatus,
            customerName: customerName,
            customerPhone: customerPhone,
            note: note,
            tables: tables,
            checkedIn: update.checkedIn,
            updatedAt: update.updatedAt
        )
    }
}

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
        if ["COMPLETED", "CANCELLED", "NO_SHOW"].contains(normalizedStatus)
            || ["LEFT", "CLEANING"].contains(normalizedService ?? "") {
            return .terminal
        }
        if checkedIn && !["EMPTY"].contains(normalizedService ?? "") {
            return .inside
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

// MARK: - Staff operations

struct WalkInRequest: Codable {
    let customerName: String
    let customerPhone: String
    let guestCount: Int
    let startTime: String?
    let durationMinutes: Int?
    let note: String?
    let checkedIn: Bool
    let tableIDs: [Int]?

    enum CodingKeys: String, CodingKey {
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case guestCount = "guest_count"
        case startTime = "start_time"
        case durationMinutes = "duration_minutes"
        case note
        case checkedIn = "checked_in"
        case tableIDs = "table_ids"
    }
}

struct WalkInResult: Codable {
    let reservationID: Int
    let reservationUUID: String
    let tables: [ReservationTableUpdate]?
    let startTime: String?
    let endTime: String?
    let checkedIn: Bool?

    enum CodingKeys: String, CodingKey {
        case reservationID = "reservation_id"
        case reservationUUID = "reservation_uuid"
        case tables
        case startTime = "start_time"
        case endTime = "end_time"
        case checkedIn = "checked_in"
    }

    var tableSummary: String {
        let names = (tables ?? []).compactMap(\.name)
        return names.isEmpty ? "Masa otomatik atandı" : names.joined(separator: ", ")
    }
}

struct ReservationUpdateRequest: Codable {
    let customerName: String?
    let customerPhone: String?
    let guestCount: Int?
    let note: String?
    /// "HH:mm"; verilirse sunucu mevcut süreyi koruyarak bitişi kaydırır.
    let startTime: String?
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case guestCount = "guest_count"
        case note
        case startTime = "start_time"
        case expectedUpdatedAt = "expected_updated_at"
    }
}

struct ReservationStatusRequest: Encodable {
    let status: String
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case expectedUpdatedAt = "expected_updated_at"
    }
}

struct ReservationNoShowRequest: Encodable {
    let reason: String
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case reason
        case expectedUpdatedAt = "expected_updated_at"
    }
}

extension Reservation {
    func updating(status: String, updatedAt: String) -> Reservation {
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
            tables: tables,
            checkedIn: checkedIn,
            updatedAt: updatedAt
        )
    }

    func updating(customerName: String, customerPhone: String, guestCount: Int, note: String?, startTime newStart: String? = nil, endTime newEnd: String? = nil, updatedAt: String) -> Reservation {
        Reservation(
            id: id,
            uuid: uuid,
            reservationDate: reservationDate,
            startTime: newStart ?? startTime,
            endTime: newEnd ?? endTime,
            guestCount: guestCount,
            status: status,
            serviceStatus: serviceStatus,
            customerName: customerName,
            customerPhone: customerPhone,
            note: note,
            tables: tables,
            checkedIn: checkedIn,
            updatedAt: updatedAt
        )
    }

    var isPending: Bool { status.uppercased() == "PENDING" }
    var isInside: Bool {
        if case .inside = operationalState() { return true }
        return false
    }
    var isTerminal: Bool { ["COMPLETED", "CANCELLED", "NO_SHOW"].contains(status.uppercased()) }
    /// Onaylı ya da bekleyen, henüz gelmemiş kayıt; iptal/gelmedi işaretlenebilir.
    var canBeClosedByStaff: Bool { !checkedIn && !isTerminal }
}

enum OperationDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func apiString(_ date: Date) -> String { apiFormatter.string(from: date) }
    static func timeString(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func today() -> String { apiString(Date()) }
    static func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
    static func isTomorrow(_ date: Date) -> Bool { calendar.isDateInTomorrow(date) }
    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// "HH:mm[:ss]" metnini verilen günün tarihine bağlar.
    static func date(onDay day: Date, time: String) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: startOfDay(day))
    }

    static func minutesBetween(_ start: String, _ end: String) -> Int? {
        let s = start.split(separator: ":").compactMap { Int($0) }
        let e = end.split(separator: ":").compactMap { Int($0) }
        guard s.count >= 2, e.count >= 2 else { return nil }
        return (e[0] * 60 + e[1]) - (s[0] * 60 + s[1])
    }

    static func timeString(adding minutes: Int, to time: String) -> String {
        let p = time.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2 else { return time }
        let total = max(0, min(23 * 60 + 59, p[0] * 60 + p[1] + minutes))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Service flow

enum ServiceAction: String, CaseIterable, Identifiable {
    case seated = "SEATED"
    case left = "LEFT"

    var id: String { rawValue }

    static func index(of serviceStatus: String?) -> Int {
        ["LEFT", "CLEANING"].contains(serviceStatus?.uppercased() ?? "") ? 1 : 0
    }

    var title: String {
        switch self {
        case .seated: "Oturdu"
        case .left: "Kalktı"
        }
    }

    var symbol: String {
        switch self {
        case .seated: "chair.lounge"
        case .left: "figure.walk.departure"
        }
    }

    var tone: MPTone {
        switch self {
        case .seated: .positive
        case .left: .info
        }
    }

    var next: ServiceAction? { self == .seated ? .left : nil }

    static func current(for serviceStatus: String?) -> ServiceAction {
        allCases[index(of: serviceStatus)]
    }

    var confirmationMessage: String {
        switch self {
        case .seated: "Misafir oturdu olarak işaretlenecek."
        case .left: "Misafir kalktı olarak işaretlenecek, rezervasyon tamamlanacak ve masa boşalacak."
        }
    }
}

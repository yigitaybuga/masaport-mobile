import Foundation

struct Reservation: Codable, Identifiable, Hashable {
    let id: Int
    let uuid: String
    let reservationDate: String
    var startTime: String
    var endTime: String
    var guestCount: Int
    var status: String
    var serviceStatus: String?
    var customerName: String
    var customerPhone: String
    var note: String?
    var tables: [VenueTable]
    var checkedIn: Bool
    var updatedAt: String

    // Misafir bağlamı (özel gün, tercih/alerji, VIP, gelmeme geçmişi, geliş teyidi). Sunucu bu alanları
    // göndermezse veya beklenmedik biçimde gönderirse yalnızca bu alanlar boş kalır; rezervasyon okunur.
    /// Özel gün anahtarı: birthday, anniversary, date_night, business, celebration.
    var occasion: String? = nil
    /// Ham tercih anahtarları (`guestPreferences`); okunur etiketler `guestDetails` içindedir.
    var guestPreferences: ReservationGuestPreferences? = nil
    /// Sunucunun etiketlenmiş özeti (`guest_details`).
    var guestDetails: ReservationGuestDetails? = nil
    /// STANDARD, SILVER, GOLD, PLATINUM.
    var vipTier: String? = nil
    /// Misafirin bu mekândaki toplam gelmeme sayısı; bu kayıt "gelmedi" ise kendisi de dahildir.
    var noShowCount: Int? = nil
    /// EXPECTED, LATE, NOTIFIED, ARRIVED, NO_SHOW.
    var arrivalStatus: String? = nil
    var arrivalNote: String? = nil
    /// Geliş durumunu işaretleyen personel; boşsa durum misafirin kendi yanıtıdır.
    var arrivalStatusBy: Int? = nil
    /// İptal nedeni kodu (`ReservationCancellationReason`) ve serbest not; eski kayıtlarda boş.
    var cancellationReason: String? = nil
    var cancellationNote: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, uuid, status, note, tables, checkedIn, updatedAt
        case reservationDate
        case startTime
        case endTime
        case guestCount
        case serviceStatus
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case occasion
        case guestPreferences
        case guestDetails = "guest_details"
        case vipTier = "customer_vip_tier"
        case noShowCount = "customer_no_show_count"
        case arrivalStatus
        case arrivalNote
        case arrivalStatusBy
        case cancellationReason
        case cancellationNote
    }
}

extension Reservation {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        uuid = try container.decode(String.self, forKey: .uuid)
        reservationDate = try container.decode(String.self, forKey: .reservationDate)
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        guestCount = try container.decode(Int.self, forKey: .guestCount)
        status = try container.decode(String.self, forKey: .status)
        serviceStatus = try container.decodeIfPresent(String.self, forKey: .serviceStatus)
        customerName = try container.decode(String.self, forKey: .customerName)
        customerPhone = try container.decode(String.self, forKey: .customerPhone)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        tables = try container.decode([VenueTable].self, forKey: .tables)
        checkedIn = try container.decode(Bool.self, forKey: .checkedIn)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)

        // Ek alanlar hoşgörülü okunur: tip uyuşmazlığı listenin tamamını düşürmesin.
        occasion = container.lenientString(forKey: .occasion)
        guestPreferences = try? container.decodeIfPresent(ReservationGuestPreferences.self, forKey: .guestPreferences)
        guestDetails = try? container.decodeIfPresent(ReservationGuestDetails.self, forKey: .guestDetails)
        vipTier = container.lenientString(forKey: .vipTier)
        noShowCount = container.lenientInt(forKey: .noShowCount)
        arrivalStatus = container.lenientString(forKey: .arrivalStatus)
        arrivalNote = container.lenientString(forKey: .arrivalNote)
        arrivalStatusBy = container.lenientInt(forKey: .arrivalStatusBy)
        cancellationReason = container.lenientString(forKey: .cancellationReason)
        cancellationNote = container.lenientString(forKey: .cancellationNote)
    }
}

/// Misafirin rezervasyonda seçtiği tercih anahtarları (`guestPreferences`).
struct ReservationGuestPreferences: Codable, Hashable {
    var dietary: [String] = []
    var seating: [String] = []

    init(dietary: [String] = [], seating: [String] = []) {
        self.dietary = dietary
        self.seating = seating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dietary = container.lenientStrings(forKey: .dietary)
        seating = container.lenientStrings(forKey: .seating)
    }
}

/// API'nin `guest_details` özeti: etiketler Türkçe ve mutfağa iletilecek alerjiler ayrıdır.
struct ReservationGuestDetails: Codable, Hashable {
    var occasion: String? = nil
    var occasionLabel: String? = nil
    var dietary: [String] = []
    var seating: [String] = []
    var allergies: [String] = []
    var hasAllergy: Bool = false

    enum CodingKeys: String, CodingKey {
        case occasion, dietary, seating, allergies
        case occasionLabel = "occasion_label"
        case hasAllergy = "has_allergy"
    }

    init(
        occasion: String? = nil,
        occasionLabel: String? = nil,
        dietary: [String] = [],
        seating: [String] = [],
        allergies: [String] = [],
        hasAllergy: Bool = false
    ) {
        self.occasion = occasion
        self.occasionLabel = occasionLabel
        self.dietary = dietary
        self.seating = seating
        self.allergies = allergies
        self.hasAllergy = hasAllergy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        occasion = container.lenientString(forKey: .occasion)
        occasionLabel = container.lenientString(forKey: .occasionLabel)
        dietary = container.lenientStrings(forKey: .dietary)
        seating = container.lenientStrings(forKey: .seating)
        allergies = container.lenientStrings(forKey: .allergies)
        hasAllergy = (try? container.decodeIfPresent(Bool.self, forKey: .hasAllergy)) ?? !allergies.isEmpty
    }
}

extension KeyedDecodingContainer {
    /// Boş metin `nil` sayılır; metin olmayan değer yok sayılır.
    func lenientString(forKey key: Key) -> String? {
        guard let value = (try? decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Sayı, ondalık veya sayısal metin kabul edilir.
    func lenientInt(forKey key: Key) -> Int? {
        if let value = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return value }
        if let value = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil, value.isFinite { return Int(value) }
        if let value = (try? decodeIfPresent(String.self, forKey: key)) ?? nil { return Int(value.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Metin dizisi; dizi değilse boş, metin olmayan elemanlar atlanır.
    func lenientStrings(forKey key: Key) -> [String] {
        if let values = (try? decodeIfPresent([String].self, forKey: key)) ?? nil {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        guard var nested = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var result: [String] = []
        while !nested.isAtEnd {
            if let value = try? nested.decode(String.self) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
            } else if (try? nested.decodeNil()) != true {
                // Metin olmayan elemanı atla; atlanamazsa döngüden çık.
                guard (try? nested.decode(LenientSkip.self)) != nil else { break }
            }
        }
        return result
    }
}

/// Dizideki tanımsız bir elemanı tüketmek için.
private struct LenientSkip: Decodable {
    init(from decoder: Decoder) throws {}
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

    // Güncellemeler kopya üzerinden yapılır; misafir bağlamı (alerji, VIP, geliş teyidi) korunur.
    func updatingTables(_ updatedTables: [ReservationTableUpdate], updatedAt: String) -> Reservation {
        var copy = self
        copy.tables = updatedTables.map { VenueTable(id: $0.id, name: $0.name ?? "Masa", capacity: $0.capacity, zone: nil, serviceStatus: nil) }
        copy.updatedAt = updatedAt
        return copy
    }

    func updatingServiceStatus(_ update: ReservationServiceStatusUpdate) -> Reservation {
        var copy = self
        copy.status = update.status
        copy.serviceStatus = update.serviceStatus
        copy.checkedIn = update.checkedIn
        copy.updatedAt = update.updatedAt
        return copy
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
    /// Kapı sırasından oturtuluyorsa sıra kaydı; sunucu kaydı ve sırayı tek işlemde kapatır.
    var walkInQueueEntryID: Int? = nil

    enum CodingKeys: String, CodingKey {
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case guestCount = "guest_count"
        case startTime = "start_time"
        case durationMinutes = "duration_minutes"
        case note
        case checkedIn = "checked_in"
        case tableIDs = "table_ids"
        case walkInQueueEntryID = "walk_in_queue_entry_id"
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
    /// Yalnızca iptalde: neden kodu ve isteğe bağlı not (`other` için not zorunlu). Boşsa gönderilmez.
    var cancellationReason: String? = nil
    var cancellationNote: String? = nil

    enum CodingKeys: String, CodingKey {
        case status
        case expectedUpdatedAt = "expected_updated_at"
        case cancellationReason = "cancellation_reason"
        case cancellationNote = "cancellation_note"
    }
}

/// API ile aynı iptal nedenleri (`api.masaport/src/utils/reservationCancellation.js`).
enum ReservationCancellationReason: String, CaseIterable, Identifiable {
    case guestRequest = "guest_request"
    case guestNoContact = "guest_no_contact"
    case duplicate
    case venueClosed = "venue_closed"
    case capacityIssue = "capacity_issue"
    case weather
    case paymentIssue = "payment_issue"
    case other

    static let noteMaxLength = 500

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guestRequest: "Misafir isteği"
        case .guestNoContact: "Misafire ulaşılamadı"
        case .duplicate: "Mükerrer kayıt"
        case .venueClosed: "Mekân kapalı"
        case .capacityIssue: "Kapasite sorunu"
        case .weather: "Hava koşulları"
        case .paymentIssue: "Ödeme sorunu"
        case .other: "Diğer"
        }
    }

    /// "Diğer" seçildiğinde kısa açıklama zorunludur.
    var requiresNote: Bool { self == .other }

    /// Not kuralı API ile aynı: en fazla 500 karakter, "Diğer"de en az 3 karakter.
    func accepts(note: String) -> Bool {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= Self.noteMaxLength && (!requiresNote || trimmed.count >= 3)
    }
}

extension Reservation {
    /// Kayıtlı iptal nedeninin etiketi; bilinmeyen kod gösterilmez.
    var cancellationReasonTitle: String? {
        cancellationReason.flatMap { ReservationCancellationReason(rawValue: $0.lowercased())?.title }
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

/// `PUT /waitlist/entry/:id/status` rotasında mekan parametresi yoktur; yetki ara katmanı (`authorize`)
/// mekanı gövdedeki `venue_id`'den okur. Sunucu kaydın gerçek mekanını ayrıca doğrular.
struct WaitlistStatusUpdateRequest: Encodable {
    let status: String
    let venueID: Int

    enum CodingKeys: String, CodingKey {
        case status
        case venueID = "venue_id"
    }
}

extension Reservation {
    func updating(status: String, updatedAt: String) -> Reservation {
        var copy = self
        copy.status = status
        copy.updatedAt = updatedAt
        return copy
    }

    func updating(customerName: String, customerPhone: String, guestCount: Int, note: String?, startTime newStart: String? = nil, endTime newEnd: String? = nil, updatedAt: String) -> Reservation {
        var copy = self
        copy.customerName = customerName
        copy.customerPhone = customerPhone
        copy.guestCount = guestCount
        copy.note = note
        copy.startTime = newStart ?? startTime
        copy.endTime = newEnd ?? endTime
        copy.updatedAt = updatedAt
        return copy
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

    /// Kalktı adımında hesap tutarı sorulur (isteğe bağlı).
    var asksForBillAmount: Bool { self == .left }
}

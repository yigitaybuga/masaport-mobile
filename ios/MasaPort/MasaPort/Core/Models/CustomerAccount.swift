import Foundation

/// Profil tercihleri; anahtarlar sunucudaki allowlist ile birebir (`PREFERENCE_OPTIONS`).
struct CustomerPreferences: Codable, Hashable {
    var dietary: [String]
    var seating: [String]

    static let empty = CustomerPreferences(dietary: [], seating: [])

    init(dietary: [String] = [], seating: [String] = []) {
        self.dietary = dietary
        self.seating = seating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dietary = try container.decodeIfPresent([String].self, forKey: .dietary) ?? []
        seating = try container.decodeIfPresent([String].self, forKey: .seating) ?? []
    }

    var isEmpty: Bool { dietary.isEmpty && seating.isEmpty }

    struct Option: Identifiable, Hashable {
        let key: String
        let label: String
        var id: String { key }
    }

    static let dietaryOptions: [Option] = [
        .init(key: "vegetarian", label: "Vejetaryen"),
        .init(key: "vegan", label: "Vegan"),
        .init(key: "gluten_free", label: "Glütensiz"),
        .init(key: "lactose_free", label: "Laktozsuz"),
        .init(key: "nut_allergy", label: "Kuruyemiş alerjisi"),
        .init(key: "seafood_allergy", label: "Deniz ürünü alerjisi"),
        .init(key: "halal", label: "Helal"),
        .init(key: "no_alcohol", label: "Alkolsüz"),
    ]

    static let seatingOptions: [Option] = [
        .init(key: "window", label: "Pencere kenarı"),
        .init(key: "outdoor", label: "Dış mekân"),
        .init(key: "indoor", label: "İç mekân"),
        .init(key: "quiet", label: "Sessiz köşe"),
        .init(key: "bar", label: "Bar"),
        .init(key: "accessible", label: "Erişilebilir masa"),
        .init(key: "high_chair", label: "Mama sandalyesi"),
    ]

    static func label(for key: String) -> String {
        (dietaryOptions + seatingOptions).first { $0.key == key }?.label ?? key
    }
}

struct CustomerAccount: Codable, Hashable {
    let id: Int
    let name: String
    let email: String
    let phone: String?
    let emailVerified: Bool?
    let marketingConsent: Bool?
    /// `YYYY-MM-DD`; eski oturum kayıtlarında bulunmayabilir.
    let birthDate: String?
    let preferences: CustomerPreferences?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, preferences
        case emailVerified = "email_verified"
        case marketingConsent = "marketing_consent"
        case birthDate = "birth_date"
        case createdAt = "created_at"
    }

    init(id: Int, name: String, email: String, phone: String?, emailVerified: Bool?, marketingConsent: Bool?, birthDate: String? = nil, preferences: CustomerPreferences? = nil, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.emailVerified = emailVerified
        self.marketingConsent = marketingConsent
        self.birthDate = birthDate
        self.preferences = preferences
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified)
        marketingConsent = try container.decodeIfPresent(Bool.self, forKey: .marketingConsent)
        birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        preferences = try container.decodeIfPresent(CustomerPreferences.self, forKey: .preferences)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    /// "AL" gibi baş harfler; avatar için.
    var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? (parts.last?.prefix(1) ?? "") : ""
        let joined = String(first + last).uppercased(with: Locale(identifier: "tr_TR"))
        return joined.isEmpty ? "M" : joined
    }

    var birthDateValue: Date? { birthDate.flatMap(DateFormat.parseAPIDay) }

    /// Profil tamamlama: ad+e-posta sabit; telefon, doğum tarihi ve tercihler isteğe bağlı.
    var completionRatio: Double {
        let optional = [phone?.nilIfBlank != nil, birthDate?.nilIfBlank != nil, preferences?.isEmpty == false]
        return Double(1 + optional.filter { $0 }.count) / Double(1 + optional.count)
    }
}

/// `/customer/auth/sessions` kaydı: giriş yapılmış bir cihaz.
struct CustomerDeviceSession: Decodable, Hashable, Identifiable {
    let id: String
    let device: String
    let platform: String
    let isCurrent: Bool
    let createdAt: String?
    let lastUsedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, device, platform
        case isCurrent = "is_current"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    var lastUsedDate: Date? { (lastUsedAt ?? createdAt).flatMap(ISO8601Parser.date(from:)) }

    var symbolName: String {
        switch platform {
        case "ios", "android": return "iphone"
        case "desktop": return "desktopcomputer"
        default: return "questionmark.square.dashed"
        }
    }
}

struct CustomerDeviceSessionsEnvelope: Decodable { let sessions: [CustomerDeviceSession] }

struct DeleteAccountRequest: Encodable { let password: String }

struct CustomerSessionResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let account: CustomerAccount

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case account
    }
}

struct CustomerRegisterPending: Decodable {
    let email: String
    let expiresAt: String?
    let resendAvailableAt: String?
    /// Yalnızca yerel/e2e ortamda döner; gerçek e-postalarda yoktur.
    let debugCode: String?

    enum CodingKeys: String, CodingKey {
        case email, expiresAt, resendAvailableAt
        case debugCode = "debug_code"
    }
}

struct CustomerRegisterRequest: Encodable {
    let name: String
    let email: String
    let phone: String?
    let password: String
    let marketingConsent: Bool

    enum CodingKeys: String, CodingKey {
        case name, email, phone, password
        case marketingConsent = "marketing_consent"
    }
}

struct CustomerVerifyRequest: Encodable {
    let email: String
    let code: String
    let installationId: String

    enum CodingKeys: String, CodingKey {
        case email, code
        case installationId = "installation_id"
    }
}

struct CustomerLoginRequest: Encodable {
    let email: String
    let password: String
    let installationId: String

    enum CodingKeys: String, CodingKey {
        case email, password
        case installationId = "installation_id"
    }
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

struct EmailRequest: Encodable { let email: String }

struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword = "new_password"
    }
}

struct UpdateAccountRequest: Encodable {
    var name: String? = nil
    var phone: String? = nil
    var marketingConsent: Bool? = nil
    /// `YYYY-MM-DD`; boş string temizler. `nil` alanı göndermez.
    var birthDate: String? = nil
    var preferences: CustomerPreferences? = nil

    enum CodingKeys: String, CodingKey {
        case name, phone, preferences
        case marketingConsent = "marketing_consent"
        case birthDate = "birth_date"
    }
}

struct AccountEnvelope: Decodable { let account: CustomerAccount }

/// `/customer/reservations` kaydı (restoran veya etkinlik).
struct CustomerReservation: Decodable, Hashable, Identifiable {
    struct Venue: Decodable, Hashable {
        let id: Int
        let name: String
        let logo: String?
        let address: String?
        let phone: String?
        let latitude: Double?
        let longitude: Double?
        let listingSlug: String?
        let image: String?

        enum CodingKeys: String, CodingKey {
            case id, name, logo, address, phone, latitude, longitude, image
            case listingSlug = "listing_slug"
        }
    }

    struct Event: Decodable, Hashable {
        struct VenueRef: Decodable, Hashable { let id: Int; let name: String; let phone: String? }
        let id: Int
        let title: String
        let imageUrl: String?
        let locationName: String?
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let venue: VenueRef?

        enum CodingKeys: String, CodingKey {
            case id, title, address, latitude, longitude, venue
            case imageUrl = "image_url"
            case locationName = "location_name"
        }
    }

    let kind: String
    let id: Int
    let uuid: String?
    let status: String?
    let reservationDate: String?
    let startTime: String?
    let endTime: String?
    let startDatetime: String?
    let endDatetime: String?
    let guestCount: Int
    let note: String?
    let checkedIn: Bool?
    let customerName: String?
    let venue: Venue?
    let event: Event?

    enum CodingKeys: String, CodingKey {
        case kind, id, uuid, status, note, venue, event
        case reservationDate = "reservation_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
        case guestCount = "guest_count"
        case checkedIn = "checked_in"
        case customerName = "customer_name"
    }

    /// Sunucu kaydını yerel bilet modeline çevirir; böylece tek liste ve tek detay ekranı kullanılır.
    func asSavedReservation() -> SavedReservation? {
        if kind == "event", let event {
            guard let start = startDatetime.flatMap(ISO8601Parser.date(from:)) else { return nil }
            return SavedReservation(
                id: UUID(uuidString: uuid ?? "") ?? UUID(),
                kind: .event,
                remoteId: id,
                remoteUUID: uuid,
                title: event.title,
                subtitle: event.locationName ?? event.address,
                image: event.imageUrl,
                startDate: start,
                endDate: endDatetime.flatMap(ISO8601Parser.date(from:)),
                timeText: DateFormat.time.string(from: start),
                guestCount: guestCount,
                status: status ?? "CONFIRMED",
                customerName: customerName ?? "",
                note: note,
                venueId: event.venue?.id,
                listingSlug: nil,
                eventId: event.id,
                address: event.address,
                phone: event.venue?.phone,
                latitude: event.latitude,
                longitude: event.longitude,
                createdAt: .now
            )
        }
        guard let reservationDate, let day = DateFormat.parseAPIDay(reservationDate) else { return nil }
        let start = combine(day: day, time: startTime ?? "00:00")
        return SavedReservation(
            id: UUID(uuidString: uuid ?? "") ?? UUID(),
            kind: .restaurant,
            remoteId: id,
            remoteUUID: uuid,
            title: venue?.name ?? "Restoran",
            subtitle: venue?.address,
            image: venue?.image ?? venue?.logo,
            startDate: start,
            endDate: endTime.map { combine(day: day, time: $0) },
            timeText: (startTime ?? "").shortTime,
            guestCount: guestCount,
            status: status ?? "CONFIRMED",
            customerName: customerName ?? "",
            note: note,
            venueId: venue?.id,
            listingSlug: venue?.listingSlug,
            eventId: nil,
            address: venue?.address,
            phone: venue?.phone,
            latitude: venue?.latitude,
            longitude: venue?.longitude,
            createdAt: .now
        )
    }

    private func combine(day: Date, time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.istanbul.dateComponents([.year, .month, .day], from: day)
        components.hour = parts.first ?? 0
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.istanbul.date(from: components) ?? day
    }
}

struct CustomerReservationsEnvelope: Decodable { let reservations: [CustomerReservation] }

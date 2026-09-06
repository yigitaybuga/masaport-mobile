import Foundation

struct ListingsQuery: Hashable {
    var limit = 24
    var offset = 0
    var orderBy: String? = nil // rating | name | createdAt | distance
    var query: String? = nil
    var cuisine: [String] = []
    var cityId: Int? = nil
    var districtId: Int? = nil
    var date: String? = nil
    var startTime: String? = nil
    var guestCount: Int? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var radiusKm: Double? = nil
    var listingIds: [Int] = []

    var hasAvailabilityIntent: Bool { date != nil || startTime != nil || guestCount != nil }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ]
        if let orderBy { items.append(.init(name: "orderBy", value: orderBy)) }
        if let query, !query.isEmpty { items.append(.init(name: "query", value: query)) }
        if !cuisine.isEmpty { items.append(.init(name: "cuisine", value: cuisine.joined(separator: ","))) }
        if let cityId { items.append(.init(name: "city_id", value: String(cityId))) }
        if let districtId { items.append(.init(name: "district_id", value: String(districtId))) }
        if let date { items.append(.init(name: "date", value: date)) }
        if let startTime { items.append(.init(name: "start_time", value: startTime)) }
        if let guestCount { items.append(.init(name: "guestCount", value: String(guestCount))) }
        if let latitude, let longitude {
            items.append(.init(name: "lat", value: String(latitude)))
            items.append(.init(name: "lng", value: String(longitude)))
            items.append(.init(name: "radius", value: String(radiusKm ?? 25)))
        }
        if !listingIds.isEmpty { items.append(.init(name: "listingIds", value: listingIds.map(String.init).joined(separator: ","))) }
        return items
    }
}

struct EventsQuery: Hashable {
    var page = 1
    var perPage = 24
    var startDate: String? = nil
    var endDate: String? = nil
    var cityId: Int? = nil
    var districtId: Int? = nil
    var categoryId: Int? = nil
    var search: String? = nil
    var sort: String? = nil

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "per_page", value: String(min(perPage, 48))),
        ]
        if let startDate { items.append(.init(name: "start_date", value: startDate)) }
        if let endDate { items.append(.init(name: "end_date", value: endDate)) }
        if let cityId { items.append(.init(name: "city_id", value: String(cityId))) }
        if let districtId { items.append(.init(name: "district_id", value: String(districtId))) }
        if let categoryId { items.append(.init(name: "category_id", value: String(categoryId))) }
        if let search, !search.isEmpty { items.append(.init(name: "search", value: search)) }
        if let sort { items.append(.init(name: "sort", value: sort)) }
        return items
    }
}

/// masaport.com'un tükettiği public uç noktaların tip güvenli sarmalayıcısı.
final class PublicAPI {
    static let shared = PublicAPI()

    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: Keşif

    func discoveryFeed(surface: String, cityId: Int?) async throws -> DiscoveryFeed {
        var items = [URLQueryItem(name: "surface", value: surface)]
        if let cityId { items.append(.init(name: "city_id", value: String(cityId))) }
        return try await client.get("/public/discovery/feed", query: items)
    }

    func discoveryLocations() async throws -> DiscoveryLocations {
        try await client.get("/public/discovery/locations")
    }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> LocationResolution? {
        let envelope: APIEnvelope<LocationResolution> = try await client.getRaw("/locations/reverse-geocode", query: [
            .init(name: "lat", value: String(latitude)),
            .init(name: "lng", value: String(longitude)),
        ])
        return envelope.data
    }

    func ipLookup() async throws -> LocationResolution? {
        let envelope: APIEnvelope<LocationResolution> = try await client.getRaw("/locations/ip-lookup")
        return envelope.data
    }

    // MARK: Restoranlar

    func listings(_ query: ListingsQuery) async throws -> ListingsPage {
        try await client.get("/public/listings", query: query.queryItems)
    }

    func listingFilters(cityId: Int?) async throws -> ListingFilters {
        var items: [URLQueryItem] = []
        if let cityId { items.append(.init(name: "city_id", value: String(cityId))) }
        return try await client.get("/public/listings/filters", query: items)
    }

    func listing(slug: String) async throws -> ListingDetail {
        let response: ListingDetail.Response = try await client.get("/public/restaurants/\(slug)")
        guard let detail = response.value else {
            throw APIError(statusCode: 404, message: "Restoran bulunamadı.", code: "NOT_FOUND")
        }
        return detail
    }

    func venueAvailability(venueId: Int, startDate: String, endDate: String, guestCount: Int) async throws -> VenueAvailability {
        try await client.get("/venues/public/\(venueId)", query: [
            .init(name: "startDate", value: startDate),
            .init(name: "endDate", value: endDate),
            .init(name: "guestCount", value: String(guestCount)),
            .init(name: "checkAvailability", value: "true"),
        ])
    }

    func createReservation(_ request: ReservationRequest) async throws -> ReservationCreated {
        // Oturum varsa rezervasyon hesaba bağlanır; yoksa anonim devam eder.
        let response: ReservationCreateResponse = try await client.post("/reservations", body: request, auth: .optional)
        guard let created = response.data else {
            throw APIError(statusCode: 500, message: response.message ?? "Rezervasyon oluşturulamadı.", code: nil)
        }
        return created
    }

    // MARK: Etkinlikler

    func events(_ query: EventsQuery) async throws -> EventsPage {
        try await client.get("/public/events", query: query.queryItems)
    }

    func eventCategories() async throws -> [EventCategory] {
        try await client.get("/public/event-categories")
    }

    func event(id: Int) async throws -> EventDetail {
        try await client.get("/events/\(id)/public")
    }

    func createEventReservation(eventId: Int, instanceId: Int, request: EventReservationRequest) async throws -> EventReservationCreated {
        let response: EventReservationCreateResponse = try await client.post("/events/\(eventId)/instances/\(instanceId)/reservations", body: request, auth: .optional)
        guard let created = response.data else {
            throw APIError(statusCode: 500, message: response.message ?? "Kayıt oluşturulamadı.", code: nil)
        }
        return created
    }

    // MARK: Tüketici hesabı

    func registerCustomer(_ request: CustomerRegisterRequest) async throws -> CustomerRegisterPending {
        try await client.post("/customer/auth/register", body: request)
    }

    func resendCustomerVerification(email: String) async throws -> CustomerRegisterPending {
        try await client.post("/customer/auth/register/resend", body: EmailRequest(email: email))
    }

    func verifyCustomerRegistration(_ request: CustomerVerifyRequest) async throws -> CustomerSessionResponse {
        try await client.post("/customer/auth/register/verify", body: request)
    }

    func loginCustomer(_ request: CustomerLoginRequest) async throws -> CustomerSessionResponse {
        try await client.post("/customer/auth/login", body: request)
    }

    func refreshCustomerSession(refreshToken: String) async throws -> CustomerSessionResponse {
        try await client.post("/customer/auth/refresh", body: RefreshTokenRequest(refreshToken: refreshToken))
    }

    func logoutCustomer(refreshToken: String) async throws {
        let _: EmptyResponse = try await client.post("/customer/auth/logout", body: RefreshTokenRequest(refreshToken: refreshToken))
    }

    func requestCustomerPasswordReset(email: String) async throws -> String {
        struct Response: Decodable {}
        let envelope: APIEnvelope<Response> = try await client.getRaw("/customer/auth/forgot-password", query: [], method: "POST", body: EmailRequest(email: email))
        return envelope.message ?? "Bu e-posta ile bir hesap varsa şifre sıfırlama bağlantısını gönderdik."
    }

    func customerAccount() async throws -> CustomerAccount {
        let envelope: AccountEnvelope = try await client.get("/customer/auth/me", auth: .required)
        return envelope.account
    }

    func updateCustomerAccount(_ request: UpdateAccountRequest) async throws -> CustomerAccount {
        let envelope: AccountEnvelope = try await client.patch("/customer/auth/me", body: request, auth: .required)
        return envelope.account
    }

    func changeCustomerPassword(_ request: ChangePasswordRequest) async throws {
        let _: EmptyResponse = try await client.post("/customer/auth/change-password", body: request, auth: .required)
    }

    func deleteCustomerAccount(password: String) async throws {
        let _: EmptyResponse = try await client.delete("/customer/auth/me", body: DeleteAccountRequest(password: password), auth: .required)
    }

    func customerSessions() async throws -> [CustomerDeviceSession] {
        let envelope: CustomerDeviceSessionsEnvelope = try await client.get("/customer/auth/sessions", auth: .required)
        return envelope.sessions
    }

    func revokeCustomerSession(id: String) async throws {
        let _: EmptyResponse = try await client.delete("/customer/auth/sessions/\(id)", body: Optional<String>.none, auth: .required)
    }

    func revokeOtherCustomerSessions() async throws {
        let _: EmptyResponse = try await client.post("/customer/auth/sessions/revoke-others", body: EmptyBody(), auth: .required)
    }

    func customerReservations() async throws -> [CustomerReservation] {
        let envelope: CustomerReservationsEnvelope = try await client.get("/customer/reservations", auth: .required)
        return envelope.reservations
    }

    // MARK: Ödeme

    func paymentConfig() async -> PaymentConfig? {
        try? await client.get("/payments/config")
    }

    func paymentStatus(paymentId: String) async throws -> PaymentStatus {
        try await client.get("/payments/\(paymentId)/public-status")
    }
}

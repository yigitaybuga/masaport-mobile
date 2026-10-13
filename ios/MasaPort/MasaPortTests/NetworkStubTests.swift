import Foundation
import Testing
@testable import MasaPort

/// Ağa çıkmadan `APIClient` üzerinden uçtan uca çözümleme: istekler bellekteki bir işleyiciyle yanıtlanır.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var body: String
    }

    struct Recorded {
        let method: String
        let path: String
        let authorization: String?
        let body: Data

        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:] }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (Recorded) -> Reply)?
    nonisolated(unsafe) private static var recorded: [Recorded] = []

    static func install(_ handler: @escaping @Sendable (Recorded) -> Reply) {
        lock.withLock {
            self.handler = handler
            recorded = []
        }
    }

    static var requests: [Recorded] { lock.withLock { recorded } }

    static func makeAPI(tokenProvider: AccessTokenProviding? = nil) -> PublicAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration))
        client.tokenProvider = tokenProvider
        return PublicAPI(client: client)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.path.replacingOccurrences(of: AppConfiguration.apiBaseURL.path, with: "", options: .anchored)
        let entry = Recorded(method: request.httpMethod ?? "GET", path: path, authorization: request.value(forHTTPHeaderField: "Authorization"), body: Self.body(of: request))
        let reply: Reply = Self.lock.withLock {
            Self.recorded.append(entry)
            return Self.handler?(entry) ?? Reply(status: 404, body: #"{"success":false,"error":"stub yok"}"#)
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class StubTokenProvider: AccessTokenProviding {
    func currentAccessToken() async -> String? { "test-access-token" }
    func refreshAccessToken() async -> String? { nil }
}

/// Stub işleyicisi paylaşıldığı için bu testler sırayla çalışır.
/// Stub işleyicileri URLSession kuyruğunda çalışır; sabitler aktöre bağlı değildir.
enum StubBodies {
    static let holdUUID = "0f8fad5b-d9cb-469f-a165-70867728950e"
    /// `payment_handoff` cevabı: tek sarmal, `data.data` yok (reservationsController).
    static let handoff = #"{"success":true,"message":"Rezervasyon ödeme tamamlanana kadar bekletiliyor.","data":{"requires_payment":true,"amount":500,"reservationHoldId":77,"reservationHoldUuid":"0f8fad5b-d9cb-469f-a165-70867728950e","holdExpiresAt":"2026-10-16T18:05:00.000Z"}}"#
    static let emptyList = #"{"success":true,"data":{"reservations":[]}}"#
}

@Suite(.serialized)
@MainActor
struct StubbedNetworkTests {

    // MARK: Görev 1 – iki cevap biçimi

    @Test func createReservationDecodesSingleEnvelopeHandoff() async throws {
        StubURLProtocol.install { _ in .init(status: 201, body: StubBodies.handoff) }
        let created = try await StubURLProtocol.makeAPI().createReservation(Self.request(handoff: true))

        #expect(created.requiresPayment == true)
        #expect(created.reservationHoldId == 77)
        #expect(created.reservationHoldUuid == StubBodies.holdUUID)
        #expect(created.holdExpiresAt == "2026-10-16T18:05:00.000Z")
        #expect(created.amount?.value == 500)
        let sent = try #require(StubURLProtocol.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.path == "/reservations")
        #expect(sent.json["payment_handoff"] as? Bool == true)
    }

    @Test func createReservationDecodesDoubleWrappedConfirmation() async throws {
        let body = #"{"success":true,"message":"Reservation created successfully","data":{"success":true,"message":"Reservation created successfully","data":{"reservation_id":451,"reservation_uuid":"5d1c8f0e-2b7a-4c39-9f6e-1a2b3c4d5e6f","management_url":"https://app.masaport.com/public/reservation/manage/5d1c8f0e-2b7a-4c39-9f6e-1a2b3c4d5e6f#token=abc","reservation_status":"CONFIRMED","start_time":"20:00","end_time":"22:00","requires_manual_approval":false,"requires_payment":false,"amount":0}}}"#
        StubURLProtocol.install { _ in .init(status: 201, body: body) }
        let created = try await StubURLProtocol.makeAPI().createReservation(Self.request(handoff: false))

        #expect(created.reservationId == 451)
        #expect(created.reservationUuid == "5d1c8f0e-2b7a-4c39-9f6e-1a2b3c4d5e6f")
        #expect(created.managementUrl?.hasSuffix("#token=abc") == true)
        #expect(created.needsPayment == false)
    }

    @Test func paymentRequiredErrorCarriesFlag() async throws {
        StubURLProtocol.install { _ in .init(status: 400, body: #"{"success":false,"error":"Payment information is required for this venue","requiresPayment":true,"amount":500}"#) }
        do {
            _ = try await StubURLProtocol.makeAPI().createReservation(Self.request(handoff: false))
            Issue.record("Hata bekleniyordu")
        } catch let error as APIError {
            #expect(error.statusCode == 400)
            #expect(error.requiresPayment == true)
            #expect(error.requestsCardPayment)
        }

        StubURLProtocol.install { _ in .init(status: 410, body: #"{"success":false,"error":"Ödeme için ayrılan süre doldu.","code":"holdExpired","requiresPayment":true}"#) }
        do {
            _ = try await StubURLProtocol.makeAPI().createReservation(Self.request(handoff: false))
            Issue.record("Hata bekleniyordu")
        } catch let error as APIError {
            #expect(error.code == "holdExpired")
            #expect(!error.requestsCardPayment)
        }
    }

    // MARK: Görev 1 + 5 – görünüm modeli

    @Test func loggedInPrepaymentUsesDateRuleAndHandsOffWithHold() async throws {
        StubURLProtocol.install { _ in .init(status: 201, body: StubBodies.handoff) }
        let viewModel = try Self.viewModel(api: StubURLProtocol.makeAPI(), account: Self.account)
        #expect(viewModel.requiresWebHandoff) // haftalık şablon değil, tarihin kuralı (provizyon)

        await viewModel.submit()

        guard case .handedOffToWeb(let url) = viewModel.outcome else {
            Issue.record("Web'e devir bekleniyordu: \(String(describing: viewModel.outcome)) \(viewModel.submitError ?? "")")
            return
        }
        #expect(viewModel.submitError == nil)
        #expect(viewModel.pendingHold?.id == 77)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "prepayment_capture_mode" }?.value == "PREAUTH")
        #expect(components.percentEncodedFragment?.contains("hold_id=77") == true)
        #expect(StubURLProtocol.requests.first?.json["time_slot_id"] as? Int == 1001)
    }

    @Test func anonymousBookingHandsOffWhenServerAsksForCard() async throws {
        StubURLProtocol.install { _ in .init(status: 400, body: #"{"success":false,"error":"Payment information is required for this venue","requiresPayment":true,"amount":500}"#) }
        // Tarihte kural yoksa uygulama ön ödeme beklemez; sunucu yine de kart isterse web'e devredilir.
        let viewModel = try Self.viewModel(api: StubURLProtocol.makeAPI(), account: nil, rule: #"{"is_full":false,"is_blocked":false}"#)
        #expect(!viewModel.requiresWebHandoff)

        await viewModel.submit()

        guard case .handedOffToWeb = viewModel.outcome else {
            Issue.record("Web'e devir bekleniyordu")
            return
        }
        #expect(viewModel.submitError == nil)
        #expect(StubURLProtocol.requests.count == 1)
    }

    // MARK: Görev 6 – yarım kalan web ödemesi

    @Test func abandonedWebPaymentReleasesHold() async throws {
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("POST", "/reservations"): return .init(status: 201, body: StubBodies.handoff)
            case ("GET", "/customer/reservations"): return .init(body: StubBodies.emptyList)
            case ("POST", "/reservations/holds/77/cancel"): return .init(body: #"{"success":true,"data":{"holdId":77,"status":"CANCELLED","cancelled":true}}"#)
            default: return .init(status: 404, body: "{}")
            }
        }
        let provider = StubTokenProvider()
        let viewModel = try Self.viewModel(api: StubURLProtocol.makeAPI(tokenProvider: provider), account: Self.account)
        await viewModel.submit()
        await viewModel.resolveWebPayment()

        #expect(viewModel.step == .details)
        #expect(viewModel.paymentNotice != nil)
        #expect(viewModel.pendingHold == nil)

        let cancel = try await Self.waitForRequest { $0.path == "/reservations/holds/77/cancel" }
        #expect(cancel.method == "POST")
        #expect(cancel.json["hold_uuid"] as? String == StubBodies.holdUUID)
        #expect(cancel.json["reason"] as? String == "flow_reset")
        // Bırakmadan önce rezervasyon iki kez aranır (hemen ve bekleme süresinden sonra).
        #expect(StubURLProtocol.requests.filter { $0.path == "/customer/reservations" }.count == 2)
        #expect(StubURLProtocol.requests.first { $0.path == "/customer/reservations" }?.authorization == "Bearer test-access-token")
    }

    @Test func completedWebPaymentIsShownAndHoldIsKept() async throws {
        let createdAt = ISO8601DateFormatter().string(from: .now)
        let list = #"{"success":true,"data":{"reservations":[{"kind":"restaurant","id":452,"uuid":"6d1c8f0e-2b7a-4c39-9f6e-1a2b3c4d5e6f","status":"CONFIRMED","reservation_date":"2026-10-16","start_time":"21:00","end_time":"23:30","guest_count":2,"checked_in":false,"created_at":"\#(createdAt)","management_url":"https://app.masaport.com/public/reservation/manage/6d1c#token=t","venue":{"id":100,"name":"Moda"}}]}}"#
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("POST", "/reservations"): return .init(status: 201, body: StubBodies.handoff)
            case ("GET", "/customer/reservations"): return .init(body: list)
            default: return .init(status: 500, body: "{}")
            }
        }
        let provider = StubTokenProvider()
        let viewModel = try Self.viewModel(api: StubURLProtocol.makeAPI(tokenProvider: provider), account: Self.account)
        await viewModel.submit()
        await viewModel.resolveWebPayment()

        guard case .confirmed(let saved, let message) = viewModel.outcome else {
            Issue.record("Onay bekleniyordu")
            return
        }
        #expect(viewModel.step == .done)
        #expect(saved.remoteId == 452)
        #expect(saved.managementLink != nil)
        #expect(message?.contains("provizyon") == true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!StubURLProtocol.requests.contains { $0.path.contains("/holds/") })
    }

    @Test func paymentCompletedDuringGraceIsNotCancelled() async throws {
        let createdAt = ISO8601DateFormatter().string(from: .now)
        let found = #"{"success":true,"data":{"reservations":[{"kind":"restaurant","id":453,"uuid":"7d1c8f0e-2b7a-4c39-9f6e-1a2b3c4d5e6f","status":"CONFIRMED","reservation_date":"2026-10-16","start_time":"21:00","guest_count":2,"created_at":"\#(createdAt)","venue":{"id":100,"name":"Moda"}}]}}"#
        let lookups = Counter()
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("POST", "/reservations"): return .init(status: 201, body: StubBodies.handoff)
            case ("GET", "/customer/reservations"):
                // İlk sorguda henüz yok; 3D Secure dönüşü bekleme süresinde işleniyor.
                return lookups.increment() == 1 ? .init(body: StubBodies.emptyList) : .init(body: found)
            default: return .init(status: 500, body: "{}")
            }
        }
        let provider = StubTokenProvider()
        let viewModel = try Self.viewModel(api: StubURLProtocol.makeAPI(tokenProvider: provider), account: Self.account)
        await viewModel.submit()
        await viewModel.resolveWebPayment()
        #expect(viewModel.step == .details)

        for _ in 0..<100 where viewModel.step != .done {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(viewModel.step == .done)
        #expect(!StubURLProtocol.requests.contains { $0.path.contains("/holds/") })
    }

    @Test func unverifiablePaymentLeavesHoldAlone() async throws {
        StubURLProtocol.install { request in
            request.path == "/reservations" ? .init(status: 201, body: StubBodies.handoff) : .init(status: 503, body: #"{"success":false,"error":"bakım"}"#)
        }
        let provider = StubTokenProvider()
        let viewModel = try Self.viewModel(api: StubURLProtocol.makeAPI(tokenProvider: provider), account: Self.account)
        await viewModel.submit()
        await viewModel.resolveWebPayment()

        #expect(viewModel.paymentNotice?.contains("doğrulayamadık") == true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!StubURLProtocol.requests.contains { $0.path.contains("/holds/") })
    }

    @Test func holdCancelReportsConversion() async throws {
        StubURLProtocol.install { _ in .init(body: #"{"success":true,"data":{"holdId":77,"status":"COMPLETED","cancelled":false}}"#) }
        let result = try await StubURLProtocol.makeAPI().cancelReservationHold(id: 77, uuid: StubBodies.holdUUID)
        #expect(result.wasConverted)
        #expect(result.cancelled == false)
    }

    // MARK: Görev 2 – bilet seçeneği isteğe gider

    @Test func freeTicketBookingSendsTicketOption() async throws {
        let body = #"{"success":true,"message":"Event reservation created successfully","data":{"success":true,"data":{"id":88,"uuid":"9d1c8f0e-2b7a-4c39-9f6e-1a2b3c4d5e6f","eventInstanceId":1010,"guestCount":2,"paymentStatus":"PAID","totalAmount":"0"}}}"#
        StubURLProtocol.install { _ in .init(body: body) }
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(Fixtures.ticketEvent.utf8))
        let instance = try #require(event.upcomingInstances.first)
        let viewModel = EventReservationViewModel(event: event, instance: instance, preferences: Fixtures.preferences(), canPayInApp: false, api: StubURLProtocol.makeAPI())
        viewModel.selectTicket(try #require(viewModel.ticketChoices.first { $0.id == "davetiye" }))
        viewModel.guestCount = 2
        viewModel.name = "Ada Lovelace"
        viewModel.email = "ada@example.com"
        viewModel.consent = true

        await viewModel.submit()

        guard case .confirmed(let saved) = viewModel.outcome else {
            Issue.record("Onay bekleniyordu: \(viewModel.submitError ?? "")")
            return
        }
        #expect(saved.remoteUUID == "9d1c8f0e-2b7a-4c39-9f6e-1a2b3c4d5e6f")
        let sent = try #require(StubURLProtocol.requests.first)
        #expect(sent.path == "/events/101/instances/1010/reservations")
        #expect(sent.json["ticket_option_id"] as? String == "davetiye")
        #expect(sent.json["guest_count"] as? Int == 2)
    }

    @Test func paidTicketWithoutInAppPaymentGoesToWeb() async throws {
        StubURLProtocol.install { _ in .init(status: 500, body: "{}") }
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(Fixtures.ticketEvent.utf8))
        let instance = try #require(event.upcomingInstances.first)
        let viewModel = EventReservationViewModel(event: event, instance: instance, preferences: Fixtures.preferences(), canPayInApp: false, api: StubURLProtocol.makeAPI())
        viewModel.selectTicket(try #require(viewModel.ticketChoices.first { $0.id == "standart" }))

        await viewModel.submit()

        guard case .handedOffToWeb(let url) = viewModel.outcome else {
            Issue.record("Web'e devir bekleniyordu")
            return
        }
        #expect(url.path.hasSuffix("/events/public/101"))
        #expect(StubURLProtocol.requests.isEmpty)
    }

    // MARK: Görev 3 – misafir bağlantısıyla durum

    @Test func guestManagementUsesLinkTokenNotSession() async throws {
        StubURLProtocol.install { _ in .init(body: #"{"success":true,"data":{"uuid":"x","status":"CANCELLED","reservationDate":"2099-01-02","startTime":"20:00","endTime":"22:00","guestCount":2}}"#) }
        let provider = StubTokenProvider()
        let managed = try await StubURLProtocol.makeAPI(tokenProvider: provider).guestManagedReservation(uuid: "x", token: "guest.token")
        #expect(managed.status == "CANCELLED")
        let sent = try #require(StubURLProtocol.requests.first)
        #expect(sent.path == "/public/reservations/x/manage")
        #expect(sent.authorization == "Bearer guest.token")
    }

    // MARK: Yardımcılar

    static let account = CustomerAccount(id: 1, name: "Ada Lovelace", email: "ada@example.com", phone: "+905551112233", emailVerified: true, marketingConsent: false)

    static func request(handoff: Bool) -> ReservationRequest {
        var request = ReservationRequest(venueId: 100, customerName: "Ada Lovelace", customerPhone: "+905551112233", customerEmail: "ada@example.com", reservationDate: "2026-10-16", guestCount: 2, timeSlotId: 1001, note: nil, kvkkConsent: true)
        request.paymentHandoff = handoff
        return request
    }

    static func viewModel(api: PublicAPI, account: CustomerAccount?, rule: String = Fixtures.preauthRule) throws -> ReservationViewModel {
        let date = try #require(DateFormat.parseAPIDay("2026-10-16"))
        let availability = try JSONDecoder().decode(VenueAvailability.self, from: Data(Fixtures.availability(date: "2026-10-16", rule: rule).utf8))
        let context = ReservationContext(venueId: 100, listingId: 1, listingSlug: "moda", name: "Moda", subtitle: "Balık · Kadıköy", image: nil, address: nil, phone: nil, latitude: nil, longitude: nil)
        let viewModel = ReservationViewModel(
            context: context,
            initialDate: date,
            initialGuests: 2,
            initialTime: "21:00",
            preloadedAvailability: availability,
            preferences: Fixtures.preferences(),
            canPayInApp: false,
            account: account,
            api: api,
            holdReleaseGrace: .milliseconds(30)
        )
        viewModel.name = "Ada Lovelace"
        viewModel.phone = "+90 555 111 22 33"
        viewModel.email = "ada@example.com"
        viewModel.kvkkAccepted = true
        viewModel.rememberMe = false
        try #require(viewModel.selectedSlot?.id == 1001)
        viewModel.continueToDetails()
        return viewModel
    }

    static func waitForRequest(_ predicate: (StubURLProtocol.Recorded) -> Bool) async throws -> StubURLProtocol.Recorded {
        for _ in 0..<100 {
            if let match = StubURLProtocol.requests.first(where: predicate) { return match }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw APIError(statusCode: 0, message: "Beklenen istek gelmedi", code: nil)
    }
}

/// Stub işleyicisi URLSession kuyruğunda çalışır; sayaç kilitle korunur.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int { lock.withLock { value += 1; return value } }
}

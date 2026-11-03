import Foundation
import Testing
@testable import MasaPortOperation

struct MasaPortOperationTests {
    @Test func operationRolesExcludeAccounting() {
        #expect(VenueRole.host.canUseOperationsApp)
        #expect(!VenueRole.accounting.canUseOperationsApp)
    }

    @Test func reservationStatusLabelsAreLocalized() {
        #expect("CONFIRMED".localizedReservationStatus == "Onaylı")
        #expect("NO_SHOW".localizedReservationStatus == "Gelmedi")
    }

    @Test func operationalTimingMarksLateArrivalsDeterministically() throws {
        let reservation = Reservation(
            id: 7,
            uuid: "B8346651-0C74-4070-A70E-0123456789AB",
            reservationDate: "2026-08-30",
            startTime: "19:30:00",
            endTime: "21:00:00",
            guestCount: 2,
            status: "CONFIRMED",
            serviceStatus: nil,
            customerName: "Zaman Testi",
            customerPhone: "5550000000",
            note: nil,
            tables: [],
            checkedIn: false,
            updatedAt: "2026-08-30T16:00:00.000Z"
        )
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let reference = try #require(formatter.date(from: "2026-08-30 20:00:00"))

        #expect(reservation.minutesUntilStart(relativeTo: reference) == -30)
        #expect(reservation.operationalState(relativeTo: reference) == .overdue(minutes: 30))
    }

    @Test func detailUpdatesKeepTheLatestVersionForTheNextMutation() {
        let reservation = Reservation(
            id: 42,
            uuid: "9F5A8D11-838B-4534-9000-0123456789AB",
            reservationDate: "2026-08-30",
            startTime: "19:30:00",
            endTime: "21:30:00",
            guestCount: 4,
            status: "CONFIRMED",
            serviceStatus: nil,
            customerName: "MasaPort Test",
            customerPhone: "5550000000",
            note: nil,
            tables: [],
            checkedIn: false,
            updatedAt: "2026-08-30T16:00:00.000Z"
        )

        let withTable = reservation.updatingTables(
            [ReservationTableUpdate(id: 7, name: "A7", capacity: 4)],
            updatedAt: "2026-08-30T16:01:00.000Z"
        )
        let seated = withTable.updatingServiceStatus(
            ReservationServiceStatusUpdate(
                serviceStatus: "SEATED",
                status: "CONFIRMED",
                checkedIn: true,
                updatedAt: "2026-08-30T16:02:00.000Z"
            )
        )

        let left = seated.updatingServiceStatus(
            ReservationServiceStatusUpdate(
                serviceStatus: "LEFT",
                status: "COMPLETED",
                checkedIn: true,
                updatedAt: "2026-08-30T17:02:00.000Z"
            )
        )

        #expect(seated.tables.map(\.name) == ["A7"])
        #expect(seated.checkedIn)
        #expect(seated.serviceStatus == "SEATED")
        #expect(seated.updatedAt == "2026-08-30T16:02:00.000Z")
        #expect(left.status == "COMPLETED")
        #expect(left.serviceStatus == "LEFT")
        #expect(left.operationalState() == .terminal)
        #expect(!left.isInside)

        let terminalButLegacySeated = seated.updatingServiceStatus(
            ReservationServiceStatusUpdate(
                serviceStatus: "SEATED",
                status: "COMPLETED",
                checkedIn: true,
                updatedAt: "2026-08-30T17:02:00.000Z"
            )
        )
        #expect(!terminalButLegacySeated.isInside)

        let legacyCleaning = seated.updatingServiceStatus(
            ReservationServiceStatusUpdate(
                serviceStatus: "CLEANING",
                status: "CONFIRMED",
                checkedIn: true,
                updatedAt: "2026-08-30T17:02:00.000Z"
            )
        )
        #expect(legacyCleaning.operationalState() == .terminal)
        #expect(!legacyCleaning.isInside)
    }

    @Test func legacyServiceStatusesCollapseIntoTheTwoServiceStages() {
        #expect(ServiceAction.allCases == [.seated, .left])
        #expect(ServiceAction.index(of: "ARRIVED") == 0)
        #expect(ServiceAction.index(of: "BILL") == 0)
        #expect(ServiceAction.index(of: "CLEANING") == 1)
        #expect("ARRIVED".localizedServiceStatus == "Oturdu")
        #expect("BILL".localizedServiceStatus == "Oturdu")
        #expect("CLEANING".localizedServiceStatus == "Kalktı")
        #expect(ServiceAction.current(for: "BILL") == .seated)
        #expect(ServiceAction.current(for: "CLEANING") == .left)
    }

    @Test func demoCheckinSeatsAndLeavingReleasesTheTable() throws {
        let store = DemoStore()
        let sampleCode = store.sampleShortCode
        let checkin = try store.respond(
            method: "POST",
            url: #require(URL(string: "https://demo.test/api/checkin/restaurant/\(sampleCode)")),
            body: Data()
        )
        #expect(checkin.0 == 200)

        let checkinReservationData = try store.respond(
            method: "GET",
            url: #require(URL(string: "https://demo.test/api/reservations/12/101")),
            body: Data()
        ).1
        let seated = try #require(JSONDecoder().decode(APIEnvelope<Reservation>.self, from: checkinReservationData).data)
        #expect(seated.serviceStatus == "SEATED")
        #expect(seated.checkedIn)

        struct ServiceRequest: Encodable {
            let serviceStatus: String
            enum CodingKeys: String, CodingKey { case serviceStatus = "service_status" }
        }
        let leaveBody = try JSONEncoder().encode(ServiceRequest(serviceStatus: "LEFT"))
        let leave = try store.respond(
            method: "PUT",
            url: #require(URL(string: "https://demo.test/api/reservations/12/101/service-status")),
            body: leaveBody
        )
        #expect(leave.0 == 200)

        let completedData = try store.respond(
            method: "GET",
            url: #require(URL(string: "https://demo.test/api/reservations/12/101")),
            body: Data()
        ).1
        let completed = try #require(JSONDecoder().decode(APIEnvelope<Reservation>.self, from: completedData).data)
        #expect(completed.status == "COMPLETED")
        #expect(completed.operationalState() == .terminal)
        #expect(!completed.isInside)

        let tablesData = try store.respond(
            method: "GET",
            url: #require(URL(string: "https://demo.test/api/tables/12")),
            body: Data()
        ).1
        let tables = try #require(JSONDecoder().decode(APIEnvelope<[VenueTable]>.self, from: tablesData).data)
        #expect(tables.first(where: { $0.id == 2 })?.serviceStatus == "EMPTY")

        let availabilityData = try store.respond(
            method: "GET",
            url: #require(URL(string: "https://demo.test/api/reservations/12/available-tables?guest_count=2")),
            body: Data()
        ).1
        let availability = try #require(JSONDecoder().decode(APIEnvelope<ReservationTableAvailability>.self, from: availabilityData).data)
        #expect(availability.tables.first(where: { $0.id == 2 })?.isAvailable == true)
    }

    @Test func waitlistPresentationKeepsStatusCountsAndContactActionsConsistent() {
        let waiting = makeWaitlistEntry(id: 1, status: "WAITING")
        let offered = makeWaitlistEntry(id: 2, status: "OFFERED")

        #expect(WaitlistFilter.all.count(in: [waiting, offered]) == 2)
        #expect(WaitlistFilter.waiting.count(in: [waiting, offered]) == 1)
        #expect(WaitlistFilter.offered.count(in: [waiting, offered]) == 1)
        #expect(offered.shortTime == "19:30")
        #expect(offered.phoneURL?.absoluteString == "tel:+905550000000")
        #expect(offered.offerHasExpired)
    }

    @Test func widgetSnapshotContainsOnlyOperationalSummary() throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let referenceDate = try #require(formatter.date(from: "2026-08-30 19:00:00"))

        let nextReservation = Reservation(
            id: 71,
            uuid: "75C92423-E9BA-4374-9723-0123456789AB",
            reservationDate: "2026-08-30",
            startTime: "19:30:00",
            endTime: "21:00:00",
            guestCount: 4,
            status: "CONFIRMED",
            serviceStatus: nil,
            customerName: "Widgetta Görünmemeli",
            customerPhone: "5551112233",
            note: "Kişisel not",
            tables: [],
            checkedIn: false,
            updatedAt: "2026-08-30T16:00:00.000Z"
        )
        let lateReservation = Reservation(
            id: 72,
            uuid: "84E14746-A4DF-428F-98F8-0123456789AB",
            reservationDate: "2026-08-30",
            startTime: "18:30:00",
            endTime: "20:00:00",
            guestCount: 2,
            status: "CONFIRMED",
            serviceStatus: nil,
            customerName: "Geciken Misafir",
            customerPhone: "5552223344",
            note: nil,
            tables: [],
            checkedIn: false,
            updatedAt: "2026-08-30T16:00:00.000Z"
        )

        let snapshot = OperationWidgetSync.makeSnapshot(
            venue: Venue(id: 4, name: "MasaPort Test", timezone: "Europe/Istanbul", logo: nil),
            reservations: [lateReservation, nextReservation],
            tables: [
                VenueTable(id: 1, name: "A1", capacity: 4, zone: nil, serviceStatus: "OCCUPIED"),
                VenueTable(id: 2, name: "A2", capacity: 4, zone: nil, serviceStatus: "EMPTY")
            ],
            waitlist: [makeWaitlistEntry(id: 1, status: "WAITING")],
            referenceDate: referenceDate
        )

        #expect(snapshot.reservationCount == 2)
        #expect(snapshot.activeTableCount == 1)
        #expect(snapshot.waitlistCount == 1)
        #expect(snapshot.overdueCount == 1)
        #expect(snapshot.nextReservation == OperationWidgetReservation(startTime: "19:30", guestCount: 4))

        let encoded = try JSONEncoder().encode(snapshot)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("Widgetta Görünmemeli"))
        #expect(!json.contains("5551112233"))
        #expect(!json.contains("Kişisel not"))
    }

    // MARK: Misafir bağlamı, hesap tutarı ve kapı sırası

    /// `GET /reservations/:venueId` yanıtındaki bir kaydın kısaltılmış hali (Prisma alanları camelCase, CRM alanları snake_case).
    private static let apiReservationJSON = """
    {
      "id": 501, "uuid": "0F8B2C7A-1111-4C1E-9A3B-0123456789AB", "venueId": 12,
      "reservationDate": "2026-11-02", "startTime": "19:30", "endTime": "21:00", "guestCount": 4,
      "status": "CONFIRMED", "serviceStatus": "EMPTY", "checkedIn": false, "updatedAt": "2026-11-02T15:00:00.000Z",
      "customer_name": "Bağlam Testi", "customer_phone": "5550000000", "note": "Pasta getirecekler",
      "tables": [{ "id": 3, "name": "A3", "capacity": 4, "zone": "Salon", "serviceStatus": "EMPTY" }],
      "occasion": "birthday",
      "guestPreferences": { "dietary": ["vegan", "nut_allergy"], "seating": ["window"] },
      "guest_details": {
        "occasion": "birthday", "occasion_label": "Doğum günü",
        "dietary": ["Vegan", "Kuruyemiş alerjisi"], "seating": ["Pencere kenarı"],
        "allergies": ["Kuruyemiş alerjisi"], "has_allergy": true
      },
      "customer_vip_tier": "GOLD", "customer_vip_score": 72, "customer_no_show_count": 2,
      "arrivalStatus": "LATE", "arrivalNote": "Misafir geliş teyidi: 30 dakika gecikeceğim. (2026-11-02 19:30)",
      "arrivalStatusAt": "2026-11-02T15:10:00.000Z", "arrivalStatusBy": null
    }
    """

    @Test func reservationDecodesGuestContextFromTheAPI() throws {
        let reservation = try JSONDecoder().decode(Reservation.self, from: Data(Self.apiReservationJSON.utf8))

        #expect(reservation.occasion == "birthday")
        #expect(reservation.guestPreferences == ReservationGuestPreferences(dietary: ["vegan", "nut_allergy"], seating: ["window"]))
        #expect(reservation.guestDetails?.occasionLabel == "Doğum günü")
        #expect(reservation.guestDetails?.hasAllergy == true)
        #expect(reservation.vipTier == "GOLD")
        #expect(reservation.noShowCount == 2)
        #expect(reservation.arrivalStatus == "LATE")
        #expect(reservation.arrivalStatusBy == nil)

        #expect(reservation.allergyLabels == ["Kuruyemiş alerjisi"])
        #expect(reservation.otherDietaryLabels == ["Vegan"])
        #expect(reservation.seatingLabels == ["Pencere kenarı"])
        #expect(reservation.occasionLabel == "Doğum günü")
        #expect(reservation.vipLevel == .gold)
        #expect(reservation.previousNoShowCount == 2)
        #expect(reservation.arrivalDelayMinutes == 30)
        #expect(reservation.arrivalIndicator?.text == "30 dk gecikecek")
        #expect(reservation.insights.map(\.kind) == [.allergy, .arrival, .vip, .occasion, .noShow, .dietary, .seating])
    }

    @Test func malformedOrMissingGuestContextKeepsTheReservationReadable() throws {
        let malformed = """
        {
          "id": 502, "uuid": "U-502", "reservationDate": "2026-11-02", "startTime": "20:00", "endTime": "21:30",
          "guestCount": 2, "status": "CONFIRMED", "serviceStatus": null, "checkedIn": false,
          "updatedAt": "2026-11-02T15:00:00.000Z", "customer_name": "Bozuk Veri", "customer_phone": "",
          "note": null, "tables": [],
          "occasion": 7, "guestPreferences": "oops", "guest_details": [],
          "customer_vip_tier": null, "customer_no_show_count": "3",
          "arrivalStatus": "", "arrivalNote": { "text": "x" }, "arrivalStatusBy": "9"
        }
        """
        let reservation = try JSONDecoder().decode(Reservation.self, from: Data(malformed.utf8))
        #expect(reservation.id == 502)
        #expect(reservation.occasion == nil)
        #expect(reservation.guestPreferences == nil)
        #expect(reservation.guestDetails == nil)
        #expect(reservation.vipTier == nil)
        #expect(reservation.noShowCount == 3)
        #expect(reservation.arrivalStatus == nil)
        #expect(reservation.arrivalNote == nil)
        #expect(reservation.arrivalStatusBy == 9)
        #expect(reservation.insights.map(\.kind) == [.noShow])

        let legacy = """
        {
          "id": 503, "uuid": "U-503", "reservationDate": "2026-11-02", "startTime": "20:00", "endTime": "21:30",
          "guestCount": 2, "status": "NO_SHOW", "checkedIn": false, "updatedAt": "2026-11-02T15:00:00.000Z",
          "customer_name": "Eski Sunucu", "customer_phone": "5550000000", "tables": [],
          "guestPreferences": { "dietary": ["gluten_free", 4, "halal"], "seating": null },
          "customer_no_show_count": 1, "arrivalStatus": "NOTIFIED", "arrivalNote": "Misafir geliş teyidi: Geliyorum."
        }
        """
        let fallback = try JSONDecoder().decode(Reservation.self, from: Data(legacy.utf8))
        // `guest_details` yoksa etiketler ham anahtarlardan üretilir.
        #expect(fallback.guestPreferences?.dietary == ["gluten_free", "halal"])
        #expect(fallback.allergyLabels == ["Glütensiz"])
        #expect(fallback.otherDietaryLabels == ["Helal"])
        // Bu kayıt "gelmedi" ise kendisi sayılmaz; kapanmış kayıtta geliş rozeti gösterilmez.
        #expect(fallback.previousNoShowCount == 0)
        #expect(fallback.arrivalIndicator == nil)
    }

    @Test func guestArrivalReplyAndStaffNoticeAreDistinguished() throws {
        var reservation = try JSONDecoder().decode(Reservation.self, from: Data(Self.apiReservationJSON.utf8))
        reservation.arrivalStatus = "notified"
        reservation.arrivalNote = "Misafir geliş teyidi: Geliyorum. (2026-11-02 19:30)"
        #expect(reservation.arrivalIndicator?.text == "Geliyorum")
        #expect(reservation.arrivalIndicator?.tone == .positive)

        reservation.arrivalStatusBy = 4
        reservation.arrivalNote = "Aradı, park yeri arıyor"
        #expect(reservation.arrivalIndicator?.text == "Haber verdi")

        reservation.arrivalStatus = "LATE"
        #expect(reservation.arrivalIndicator?.text == "Gecikti")

        reservation.checkedIn = true
        #expect(reservation.arrivalIndicator == nil)
    }

    @Test func localUpdatesAndDemoRoundTripKeepTheGuestContext() throws {
        let reservation = try JSONDecoder().decode(Reservation.self, from: Data(Self.apiReservationJSON.utf8))
        let seated = reservation
            .updatingTables([ReservationTableUpdate(id: 4, name: "A4", capacity: 4)], updatedAt: "2026-11-02T15:20:00.000Z")
            .updatingServiceStatus(ReservationServiceStatusUpdate(serviceStatus: "SEATED", status: "CONFIRMED", checkedIn: true, updatedAt: "2026-11-02T15:21:00.000Z"))
            .updating(status: "CONFIRMED", updatedAt: "2026-11-02T15:22:00.000Z")
        #expect(seated.tables.map(\.name) == ["A4"])
        #expect(seated.checkedIn)
        #expect(seated.guestDetails == reservation.guestDetails)
        #expect(seated.vipTier == "GOLD")
        #expect(seated.noShowCount == 2)

        let roundTrip = try JSONDecoder().decode(Reservation.self, from: JSONEncoder().encode(reservation))
        #expect(roundTrip == reservation)
    }

    @Test func billAmountInputMatchesTheServerFormat() {
        #expect(BillAmountInput.parse("") == .empty)
        #expect(BillAmountInput.parse("   ") == .empty)
        #expect(BillAmountInput.parse("2500") == .valid("2500"))
        #expect(BillAmountInput.parse("2500,5") == .valid("2500.5"))
        #expect(BillAmountInput.parse("2500.50") == .valid("2500.50"))
        #expect(BillAmountInput.parse("₺ 2 500,00") == .valid("2500.00"))
        #expect(BillAmountInput.parse("0") == .valid("0"))
        #expect(BillAmountInput.parse("2.500") == .invalid)
        #expect(BillAmountInput.parse("2.500,50") == .invalid)
        #expect(BillAmountInput.parse("123456789") == .invalid)
        #expect(BillAmountInput.parse(",50") == .invalid)
        #expect(BillAmountInput.parse("12a") == .invalid)
        #expect(BillAmountInput.parse("-5") == .invalid)
    }

    @Test func serviceStatusRequestSendsTheBillAmountOnlyWhenGiven() throws {
        struct Sent: Decodable {
            let serviceStatus: String
            let expectedUpdatedAt: String
            let billAmount: String?
            enum CodingKeys: String, CodingKey {
                case serviceStatus = "service_status"
                case expectedUpdatedAt = "expected_updated_at"
                case billAmount = "bill_amount"
            }
        }
        let withAmount = try JSONDecoder().decode(Sent.self, from: JSONEncoder().encode(
            ServiceStatusUpdateRequest(serviceStatus: "LEFT", expectedUpdatedAt: "2026-11-02T15:00:00.000Z", billAmount: "2500.50")
        ))
        #expect(withAmount.billAmount == "2500.50")
        #expect(withAmount.serviceStatus == "LEFT")

        let encoded = try JSONEncoder().encode(ServiceStatusUpdateRequest(serviceStatus: "LEFT", expectedUpdatedAt: "2026-11-02T15:00:00.000Z"))
        #expect(!(String(data: encoded, encoding: .utf8) ?? "").contains("bill_amount"))
    }

    @Test func cancellationReasonsMatchTheAPIAndEncodeOnlyWhenGiven() throws {
        #expect(ReservationCancellationReason.allCases.map(\.rawValue) == [
            "guest_request", "guest_no_contact", "duplicate", "venue_closed",
            "capacity_issue", "weather", "payment_issue", "other"
        ])
        #expect(ReservationCancellationReason.other.accepts(note: "  ab ") == false)
        #expect(ReservationCancellationReason.other.accepts(note: "Rezervasyon tekrarlandı"))
        #expect(ReservationCancellationReason.guestRequest.accepts(note: ""))
        #expect(!ReservationCancellationReason.guestRequest.accepts(note: String(repeating: "a", count: 501)))

        let cancel = try #require(String(data: JSONEncoder().encode(ReservationStatusRequest(
            status: "CANCELLED", expectedUpdatedAt: "2026-11-02T15:00:00.000Z",
            cancellationReason: "other", cancellationNote: "Etkinlik ertelendi"
        )), encoding: .utf8))
        #expect(cancel.contains("\"cancellation_reason\":\"other\""))
        #expect(cancel.contains("\"cancellation_note\":\"Etkinlik ertelendi\""))
        let confirm = try #require(String(data: JSONEncoder().encode(ReservationStatusRequest(
            status: "CONFIRMED", expectedUpdatedAt: "2026-11-02T15:00:00.000Z"
        )), encoding: .utf8))
        #expect(!confirm.contains("cancellation"))

        var reservation = try JSONDecoder().decode(Reservation.self, from: Data(Self.apiReservationJSON.utf8))
        #expect(reservation.cancellationReason == nil)
        reservation.cancellationReason = "WEATHER"
        #expect(reservation.cancellationReasonTitle == "Hava koşulları")
        reservation.cancellationReason = "unknown_code"
        #expect(reservation.cancellationReasonTitle == nil)
    }

    @Test func walkInQueueDecodesTheWebPanelPayload() throws {
        let json = """
        {
          "active": [
            { "id": 7, "uuid": "q-7", "customerName": "Kapı Testi", "customerPhone": "+905550000000", "customerEmail": null,
              "partySize": 3, "quotedWaitMinutes": 15, "note": "Bahçe", "status": "WAITING", "position": 1,
              "waitedMinutes": 4, "remainingMinutes": 11, "overdue": false, "notifiedAt": null, "seatedAt": null,
              "closedAt": null, "reservationId": null, "createdAt": "2026-11-02T16:00:00.000Z",
              "statusUrl": "https://app.masaport.com/public/sira/q-7" },
            { "id": 8, "customerName": "Telefonsuz", "customerPhone": null, "partySize": 2,
              "quotedWaitMinutes": 20, "status": "NOTIFIED", "position": 2, "createdAt": "2026-11-02T16:05:00Z" }
          ],
          "recent": [],
          "minutesPerParty": 9,
          "suggestedQuoteMinutes": 25
        }
        """
        let snapshot = try JSONDecoder().decode(WalkInQueueSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.active.count == 2)
        #expect(snapshot.suggestedQuoteMinutes == 25)
        let first = snapshot.active[0]
        #expect(first.customerEmail == nil)
        #expect(first.phoneURL?.absoluteString == "tel:+905550000000")
        #expect(first.walkInPrefill.queueEntryID == 7)
        #expect(first.walkInPrefill.guestCount == 3)

        let joined = try #require(first.joinedAt)
        #expect(first.waitedMinutes(at: joined.addingTimeInterval(10 * 60)) == 10)
        #expect(!first.isOverdue(at: joined.addingTimeInterval(15 * 60)))
        #expect(first.isOverdue(at: joined.addingTimeInterval(16 * 60)))

        let second = snapshot.active[1]
        #expect(second.isNotified)
        #expect(!second.hasContactChannel)
        #expect(second.joinedAt != nil)
        #expect(WalkInQueueMessage.ready(
            WalkInQueueNotifyResult(entry: second, delivery: WalkInQueueDelivery(status: "SKIPPED", reason: "Telefon yok."), emailDelivery: nil),
            entry: second
        ) == "Telefonsuz haberdar edildi olarak işaretlendi. Misafire sözlü olarak haber verin.")
        #expect(WalkInQueueMessage.ready(
            WalkInQueueNotifyResult(entry: first, delivery: WalkInQueueDelivery(status: "SENT", reason: nil), emailDelivery: nil),
            entry: first
        ).contains("WhatsApp ile gönderildi"))
    }

    private func makeWaitlistEntry(id: Int, status: String) -> WaitlistEntry {
        WaitlistEntry(
            id: id,
            venueID: 12,
            timeSlotID: 4,
            reservationDate: "2026-08-30",
            guestCount: 3,
            customerName: "Bekleme Testi",
            customerPhone: "+90 (555) 000 00 00",
            customerEmail: nil,
            status: status,
            source: "MOBILE",
            note: nil,
            createdAt: "2026-08-30T16:00:00.000Z",
            offerExpiresAt: "2000-01-01T00:00:00.000Z",
            timeSlot: WaitlistTimeSlot(
                id: 4,
                startTime: "19:30:00",
                endTime: "21:00:00",
                durationMinutes: 90
            )
        )
    }
}

// MARK: - Oturum kurtarma, sürüm ve bekleme listesi istekleri

/// Ağ yerine test işleyicisine giden istekler. Statik işleyici kullandığı için yalnızca
/// `.serialized` süit içinde kullanılır.
final class StubURLProtocol: URLProtocol {
    enum Response {
        case http(Int, Data)
        case offline
    }

    typealias Handler = @Sendable (URLRequest, Data) async -> Response

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func makeSession(handler: @escaping Handler) -> URLSession {
        lock.withLock { self.handler = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let body = Self.readBody(of: request)
        guard let handler = Self.lock.withLock({ Self.handler }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        Task {
            switch await handler(request, body) {
            case .http(let statusCode, let data):
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            case .offline:
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            }
        }
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// İşleyiciler eşzamanlı çalışır; sayaç ve kayıtlar kilitle korunur.
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var bodies: [String: Data] = [:]

    func record(_ key: String, body: Data = Data()) {
        lock.withLock {
            counts[key, default: 0] += 1
            bodies[key] = body
        }
    }

    func count(_ key: String) -> Int { lock.withLock { counts[key, default: 0] } }
    func body(_ key: String) -> Data? { lock.withLock { bodies[key] } }
}

final class InMemoryCredentials: SessionCredentialStore {
    var storedAccessToken: String?
    var storedRefreshToken: String?

    func refreshToken() throws -> String? { storedRefreshToken }
    func installationID() throws -> String { "8C0E3D4A-5B6C-4D7E-8F90-0123456789AB" }

    func save(accessToken: String, refreshToken: String) throws {
        storedAccessToken = accessToken
        storedRefreshToken = refreshToken
    }

    func deleteSession() {
        storedAccessToken = nil
        storedRefreshToken = nil
    }
}

private struct TestEnvelope<Value: Encodable>: Encodable {
    let success: Bool
    let data: Value?
    var error: String? = nil
    var code: String? = nil
}

private func okJSON<Value: Encodable>(_ value: Value) -> StubURLProtocol.Response {
    .http(200, (try? JSONEncoder().encode(TestEnvelope(success: true, data: value))) ?? Data())
}

private func failureJSON(_ statusCode: Int, error: String, code: String? = nil) -> StubURLProtocol.Response {
    .http(statusCode, (try? JSONEncoder().encode(TestEnvelope<EmptyResponse>(success: false, data: nil, error: error, code: code))) ?? Data())
}

private func apiPath(_ request: URLRequest) -> String {
    let path = request.url?.path ?? ""
    return path.hasPrefix("/api") ? String(path.dropFirst(4)) : path
}

private func authPayload(accessToken: String, refreshToken: String) -> MobileAuthPayload {
    MobileAuthPayload(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresIn: 900,
        tokenType: "Bearer",
        session: MobileSession(id: "test-session", expiresAt: "2099-01-01T00:00:00.000Z", installationID: nil),
        user: OperationUser(
            id: 1,
            name: "Host Test",
            email: "host@example.com",
            venueRoles: [VenueRoleAssignment(venueId: 12, role: .host)]
        ),
        venues: [Venue(id: 12, name: "MasaPort Test", timezone: "Europe/Istanbul", logo: nil)]
    )
}

@MainActor
@Suite(.serialized)
struct SessionAndConcurrencyTests {
    @Test func statusChangeAndNoShowUseTheServerVersionForTheNextMutation() async throws {
        let store = DemoStore()
        let api = APIClient(session: StubURLProtocol.makeSession { request, body in
            let (statusCode, data) = store.respond(method: request.httpMethod ?? "GET", url: request.url!, body: body)
            return .http(statusCode, data)
        })
        api.setAccessToken("test-access")

        let pending: Reservation = try await api.get("/reservations/12/107")
        #expect(pending.status == "PENDING")
        let model = ReservationDetailViewModel(reservation: pending, venueID: 12, api: api)

        #expect(await model.updateStatus("CONFIRMED"))
        let confirmed: Reservation = try await api.get("/reservations/12/107")
        #expect(model.reservation.status == "CONFIRMED")
        #expect(model.reservation.updatedAt == confirmed.updatedAt)

        // Demo sunucu da API gibi `expected_updated_at` için birebir eşleşme ister; uydurulmuş sürüm 409 alırdı.
        #expect(await model.updateDetails(customerName: pending.customerName, customerPhone: pending.customerPhone, guestCount: 4, note: "Pencere kenarı"))
        #expect(model.errorMessage == nil)

        #expect(await model.markNoShow(reason: "Aradık, ulaşılamadı"))
        let noShow: Reservation = try await api.get("/reservations/12/107")
        #expect(noShow.status == "NO_SHOW")
        #expect(model.reservation.updatedAt == noShow.updatedAt)
        #expect(model.errorMessage == nil)
    }

    @Test func failedPostMutationReloadIsRetriedBeforeTheNextMutation() async throws {
        let store = DemoStore()
        let log = RequestLog()
        let api = APIClient(session: StubURLProtocol.makeSession { request, body in
            let method = request.httpMethod ?? "GET"
            if method == "GET", apiPath(request) == "/reservations/12/107", log.count("status") == 1, log.count("failed-get") == 0 {
                // Onaydan hemen sonraki yeniden çekme ağ hatasına düşer.
                log.record("failed-get")
                return .offline
            }
            if method == "PUT", apiPath(request).hasSuffix("/status") { log.record("status") }
            let (statusCode, data) = store.respond(method: method, url: request.url!, body: body)
            return .http(statusCode, data)
        })
        api.setAccessToken("test-access")

        let pending: Reservation = try await api.get("/reservations/12/107")
        let model = ReservationDetailViewModel(reservation: pending, venueID: 12, api: api)

        #expect(await model.updateStatus("CONFIRMED"))
        #expect(log.count("failed-get") == 1)
        // Sürüm uydurulmaz: ekranda yeni durum görünür, sürüm eskide kalır ve sonraki işlemden önce tazelenir.
        #expect(model.reservation.status == "CONFIRMED")
        #expect(model.reservation.updatedAt == pending.updatedAt)

        #expect(await model.markNoShow(reason: "Aradık, ulaşılamadı"))
        let server: Reservation = try await api.get("/reservations/12/107")
        #expect(server.status == "NO_SHOW")
        #expect(model.reservation.updatedAt == server.updatedAt)
        #expect(model.errorMessage == nil)
    }

    @Test func unauthorizedRequestRefreshesOnceAndRetriesWithTheNewToken() async throws {
        let log = RequestLog()
        let api = APIClient(session: StubURLProtocol.makeSession { request, _ in
            log.record(request.value(forHTTPHeaderField: "Authorization") ?? "none")
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" else {
                return .http(401, Data(#"{"error":"Session expired"}"#.utf8))
            }
            return okJSON([VenueTable(id: 1, name: "A1", capacity: 2, zone: nil, serviceStatus: "EMPTY")])
        })
        api.setAccessToken("stale")
        api.setRefreshHandler {
            log.record("refresh")
            return .refreshed(accessToken: "fresh")
        }

        let tables: [VenueTable] = try await api.get("/tables/12")
        #expect(tables.map(\.name) == ["A1"])
        #expect(log.count("refresh") == 1)
        #expect(log.count("Bearer stale") == 1)
        #expect(log.count("Bearer fresh") == 1)
        #expect(api.currentAccessToken == "fresh")
    }

    @Test func concurrentUnauthorizedRequestsShareASingleRefresh() async throws {
        let log = RequestLog()
        let api = APIClient(session: StubURLProtocol.makeSession { request, _ in
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" else {
                log.record("401")
                return .http(401, Data(#"{"error":"Session expired"}"#.utf8))
            }
            return okJSON([VenueTable]())
        })
        api.setAccessToken("stale")
        api.setRefreshHandler {
            log.record("refresh")
            // Diğer isteklerin 401'i yenileme sürerken gelsin.
            try? await Task.sleep(for: .milliseconds(200))
            return .refreshed(accessToken: "fresh")
        }

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    let tables: [VenueTable] = try await api.get("/tables/12")
                    return tables.count
                }
            }
            var completed = 0
            for try await _ in group { completed += 1 }
            return completed
        }

        #expect(results == 6)
        #expect(log.count("refresh") == 1)
        #expect(log.count("401") >= 1)
    }

    @Test func rejectedRefreshClearsTheLocalSession() async throws {
        let log = RequestLog()
        let credentials = InMemoryCredentials()
        let api = APIClient(session: StubURLProtocol.makeSession { request, _ in
            switch apiPath(request) {
            case "/mobile/auth/login":
                return okJSON(authPayload(accessToken: "access-1", refreshToken: "refresh-1"))
            case "/mobile/auth/refresh":
                log.record("refresh")
                return failureJSON(401, error: "Oturum süresi doldu", code: "UNAUTHORIZED")
            default:
                log.record("tables")
                return .http(401, Data(#"{"error":"Session expired"}"#.utf8))
            }
        })
        final class Flag { var value = false }
        let widgetCleared = Flag()
        let session = SessionStore(api: api, credentials: credentials, clearSharedSnapshot: { widgetCleared.value = true })

        try await session.login(email: "host@example.com", password: "parola")
        #expect(session.state == .signedIn)
        #expect(credentials.storedRefreshToken == "refresh-1")

        await #expect(throws: APIError.self) {
            let _: [VenueTable] = try await api.get("/tables/12")
        }

        #expect(log.count("refresh") == 1)
        #expect(log.count("tables") == 1)
        #expect(session.state == .signedOut)
        #expect(session.signOutNotice == SessionStore.expiredSessionMessage)
        #expect(session.activeVenue == nil)
        #expect(credentials.storedRefreshToken == nil)
        #expect(credentials.storedAccessToken == nil)
        #expect(api.currentAccessToken == nil)
        #expect(widgetCleared.value)
    }

    @Test func offlineRefreshKeepsTheSession() async throws {
        let credentials = InMemoryCredentials()
        let api = APIClient(session: StubURLProtocol.makeSession { request, _ in
            switch apiPath(request) {
            case "/mobile/auth/login":
                return okJSON(authPayload(accessToken: "access-1", refreshToken: "refresh-1"))
            case "/mobile/auth/refresh":
                return .offline
            default:
                return .http(401, Data(#"{"error":"Session expired"}"#.utf8))
            }
        })
        let session = SessionStore(api: api, credentials: credentials, clearSharedSnapshot: {})
        try await session.login(email: "host@example.com", password: "parola")

        await #expect(throws: APIError.self) {
            let _: [VenueTable] = try await api.get("/tables/12")
        }

        #expect(session.state == .signedIn)
        #expect(session.signOutNotice == nil)
        #expect(credentials.storedRefreshToken == "refresh-1")
        #expect(api.currentAccessToken == "access-1")
    }

    @Test func waitlistStatusUpdatesSendTheActiveVenueID() async throws {
        struct StatusResult: Encodable { let id: Int; let status: String }
        struct SentBody: Decodable {
            let status: String
            let venueID: Int
            enum CodingKeys: String, CodingKey {
                case status
                case venueID = "venue_id"
            }
        }
        let log = RequestLog()
        let api = APIClient(session: StubURLProtocol.makeSession { request, body in
            let path = apiPath(request)
            if request.httpMethod == "PUT", path == "/waitlist/entry/201/status" {
                log.record(path, body: body)
                let sent = try? JSONDecoder().decode(SentBody.self, from: body)
                return okJSON(StatusResult(id: 201, status: sent?.status ?? ""))
            }
            // Listeyi yeniden yükleme bu testin konusu değil; widget özetine de yazılmaz.
            return failureJSON(404, error: "Not found")
        })
        api.setAccessToken("test-access")
        let entry = WaitlistEntry(
            id: 201, venueID: 12, timeSlotID: 4, reservationDate: "2026-08-30", guestCount: 2,
            customerName: "Bekleme Testi", customerPhone: "5550000000", customerEmail: nil,
            status: "WAITING", source: "WEB", note: nil, createdAt: nil, offerExpiresAt: nil, timeSlot: nil
        )

        #expect(await WaitlistViewModel(api: api).cancel(entry, venueID: 12))
        let cancelled = try JSONDecoder().decode(SentBody.self, from: #require(log.body("/waitlist/entry/201/status")))
        #expect(cancelled.status == "CANCELLED")
        #expect(cancelled.venueID == 12)

        #expect(await TodayViewModel(api: api).markConverted(entry, venue: Venue(id: 13, name: "Teras", timezone: nil, logo: nil)))
        let converted = try JSONDecoder().decode(SentBody.self, from: #require(log.body("/waitlist/entry/201/status")))
        #expect(converted.status == "CONVERTED")
        #expect(converted.venueID == 13)
        #expect(log.count("/waitlist/entry/201/status") == 2)
    }

    @Test func leavingSendsTheBillAmountWithTheCurrentVersion() async throws {
        let store = DemoStore()
        let log = RequestLog()
        let api = APIClient(session: StubURLProtocol.makeSession { request, body in
            if request.httpMethod == "PUT", apiPath(request).hasSuffix("/service-status") {
                log.record("service-status", body: body)
            }
            let (statusCode, data) = store.respond(method: request.httpMethod ?? "GET", url: request.url!, body: body)
            return .http(statusCode, data)
        })
        api.setAccessToken("test-access")
        let model = HostDeskViewModel(api: api)
        await model.load(venueID: 12)
        let seated = try #require(model.reservations.first { $0.id == 102 })
        #expect(seated.isInside)

        #expect(await model.updateServiceStatus(seated, to: .left, billAmount: "2500.50", venueID: 12))
        struct Sent: Decodable {
            let billAmount: String?
            let expectedUpdatedAt: String
            enum CodingKeys: String, CodingKey {
                case billAmount = "bill_amount"
                case expectedUpdatedAt = "expected_updated_at"
            }
        }
        let sent = try JSONDecoder().decode(Sent.self, from: #require(log.body("service-status")))
        #expect(sent.billAmount == "2500.50")
        #expect(sent.expectedUpdatedAt == seated.updatedAt)
        #expect(model.reservations.first { $0.id == 102 }?.status == "COMPLETED")
        // Demo verisi: misafir bağlamı listede gelir, kapı sırası da bugünün yüklemesine eklenir.
        #expect(model.reservations.first { $0.id == 104 }?.allergyLabels == ["Kuruyemiş alerjisi"])
        #expect(!model.walkInQueue.isEmpty)
    }

    @Test func cancellingSendsTheReasonAndKeepsItOnTheRecord() async throws {
        let store = DemoStore()
        let api = APIClient(session: StubURLProtocol.makeSession { request, body in
            let (statusCode, data) = store.respond(method: request.httpMethod ?? "GET", url: request.url!, body: body)
            return .http(statusCode, data)
        })
        api.setAccessToken("test-access")
        let reservation: Reservation = try await api.get("/reservations/12/109")
        let model = ReservationDetailViewModel(reservation: reservation, venueID: 12, api: api)

        // "Diğer" açıklamasız reddedilir; kayıt değişmez.
        #expect(await model.updateStatus("CANCELLED", cancellationReason: .other, cancellationNote: " ") == false)
        #expect(model.reservation.status == "CONFIRMED")

        #expect(await model.updateStatus("CANCELLED", cancellationReason: .other, cancellationNote: "Grup ertelendi"))
        #expect(model.reservation.status == "CANCELLED")
        #expect(model.reservation.cancellationReason == "other")
        #expect(model.reservation.cancellationNote == "Grup ertelendi")
        #expect(model.reservation.cancellationReasonTitle == "Diğer")
    }

    @Test func walkInQueueAddNotifyAndSeatThroughTheWalkInForm() async throws {
        let store = DemoStore()
        let api = APIClient(session: StubURLProtocol.makeSession { request, body in
            let (statusCode, data) = store.respond(method: request.httpMethod ?? "GET", url: request.url!, body: body)
            return .http(statusCode, data)
        })
        api.setAccessToken("test-access")
        let queue = WalkInQueueViewModel(api: api)
        await queue.load(venueID: 12)
        let initialCount = queue.entries.count

        let added = await queue.add(
            WalkInQueueCreateRequest(customerName: "Sıra Testi", customerPhone: "+90 555 000 00 00", customerEmail: nil,
                                     partySize: 2, quotedWaitMinutes: 20, note: nil, sendLink: true),
            venueID: 12
        )
        #expect(added?.contains("sıraya eklendi") == true)
        let entry = try #require(queue.entries.first { $0.customerName == "Sıra Testi" })
        #expect(queue.entries.count == initialCount + 1)
        #expect(entry.position == queue.entries.count)

        #expect(await queue.notifyReady(entry, venueID: 12) != nil)
        #expect(queue.entries.first { $0.id == entry.id }?.isNotified == true)

        // "Oturt": walk-in formu sıra kaydıyla gönderilir; kayıt oluşunca sıra kapanır.
        let walkIn = WalkInViewModel(api: api, prefill: entry.walkInPrefill)
        #expect(walkIn.customerName == "Sıra Testi")
        #expect(await walkIn.submit(venueID: 12))
        await queue.load(venueID: 12)
        #expect(!queue.entries.contains { $0.id == entry.id })

        // Aynı kayıt ikinci kez oturtulamaz (başka cihaz yarışı).
        #expect(await WalkInViewModel(api: api, prefill: entry.walkInPrefill).submit(venueID: 12) == false)

        let remaining = try #require(queue.entries.first)
        #expect(await queue.close(remaining, status: "CANCELLED", venueID: 12) != nil)
        #expect(!queue.entries.contains { $0.id == remaining.id })
        #expect(queue.errorMessage == nil)
    }

    @Test func loadGateSkipsOverlappingSilentRefreshesAndStaleResponses() throws {
        var gate = LoadGate()
        let firstToken = gate.begin(silent: false)
        let first = try #require(firstToken)
        // Süren yüklemenin üstüne sessiz tazeleme binmez.
        let skipped = gate.begin(silent: true)
        #expect(skipped == nil)

        // Kullanıcının başlattığı yükleme her zaman çalışır; eski yanıt artık güncel sayılmaz.
        let secondToken = gate.begin(silent: false)
        let second = try #require(secondToken)
        #expect(!gate.isCurrent(first))
        #expect(gate.isCurrent(second))
        gate.end(first)
        #expect(gate.isFetching)
        gate.end(second)
        #expect(!gate.isFetching)
        let resumed = gate.begin(silent: true)
        #expect(resumed != nil)
    }
}

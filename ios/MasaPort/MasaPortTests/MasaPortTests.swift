import Foundation
import Testing
@testable import MasaPort

struct ModelDecodingTests {
    @Test func parsesCanonicalUniversalLinks() throws {
        let restaurant = try #require(URL(string: "https://masaport.com/istanbul/restoranlar/test-mekan"))
        #expect(AppDeepLink.parse(restaurant) == .listing(slug: "test-mekan"))

        let event = try #require(URL(string: "https://www.masaport.com/etkinlikler/yaz-konseri"))
        #expect(AppDeepLink.parse(event) == .event(identifier: "yaz-konseri"))
    }

    @Test func parsesCustomSchemeLinks() throws {
        let restaurant = try #require(URL(string: "masaport://restaurant/test-mekan"))
        #expect(AppDeepLink.parse(restaurant) == .listing(slug: "test-mekan"))

        let event = try #require(URL(string: "masaport://event/42"))
        #expect(AppDeepLink.parse(event)?.route == .event(id: 42))
    }

    @Test func ignoresUnrelatedLinks() throws {
        let url = try #require(URL(string: "https://example.com/restaurant/test-mekan"))
        #expect(AppDeepLink.parse(url) == nil)
    }

    @Test func decodesDecimalStringsAndNumbers() throws {
        let json = #"{"id":1,"name":"Test","slug":"test","rating":"4.80000000","latitude":"41.02","longitude":29.01}"#
        let card = try JSONDecoder().decode(ListingCard.self, from: Data(json.utf8))
        #expect(card.rating?.value == 4.8)
        #expect(card.latitude?.value == 41.02)
        #expect(card.longitude?.value == 29.01)
    }

    @Test func decodesDoubleNestedReservationResponse() throws {
        let json = #"{"success":true,"message":"ok","data":{"reservation_id":7,"reservation_status":"CONFIRMED","start_time":"19:30","requires_payment":false}}"#
        let response = try JSONDecoder().decode(ReservationCreateResponse.self, from: Data(json.utf8))
        #expect(response.data?.reservationId == 7)
        #expect(response.data?.needsPayment == false)
    }

    @Test func encodesAndDecodesAuthenticatedPaymentHandoff() throws {
        var request = ReservationRequest(
            venueId: 1,
            customerName: "Ada Lovelace",
            customerPhone: "+905551112233",
            customerEmail: "ada@example.com",
            reservationDate: "2026-09-09",
            guestCount: 2,
            timeSlotId: 42,
            note: "Pencere kenarı",
            kvkkConsent: true
        )
        request.paymentHandoff = true
        let requestObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(requestObject["payment_handoff"] as? Bool == true)

        let json = #"{"success":true,"data":{"requires_payment":true,"amount":500,"reservationHoldId":77,"reservationHoldUuid":"0f8fad5b-d9cb-469f-a165-70867728950e","holdExpiresAt":"2026-09-09T17:15:00.000Z"}}"#
        let response = try JSONDecoder().decode(ReservationCreateResponse.self, from: Data(json.utf8))
        #expect(response.data?.needsPayment == true)
        #expect(response.data?.reservationHoldId == 77)
        #expect(response.data?.reservationHoldUuid == "0f8fad5b-d9cb-469f-a165-70867728950e")
    }

    @Test func weekendRangeStartsOnSaturday() {
        var calendar = Calendar.istanbul
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        // 2026-09-02 Çarşamba
        let wednesday = DateFormat.parseAPIDay("2026-09-02")!
        let bounds = EventsDateRange.weekend.bounds(now: wednesday, calendar: calendar)
        #expect(bounds.start == "2026-09-05")
        #expect(bounds.end == "2026-09-06")
    }

    @Test func slotOptionsUseIsoWeekday() {
        let slot = PublicSlot(id: 1, startTime: "19:00", endTime: "21:00", durationMinutes: 120, bookingMode: "STANDARD", requiresManualApproval: false, bookingMessage: nil, minimumSpendRequired: false, minimumSpendSummary: nil, prepaymentRequired: false, prepaymentSummary: nil, prepaymentTotalAmount: nil)
        let availability = VenueAvailability(id: 1, name: "V", timezone: nil, texts: nil, slots: ["7": [slot]], blockedDates: nil, availability: nil, isSubscriptionActive: true)
        let sunday = DateFormat.parseAPIDay("2026-09-06")!
        #expect(availability.slotOptions(for: sunday).count == 1)
        let monday = DateFormat.parseAPIDay("2026-09-07")!
        #expect(availability.slotOptions(for: monday).isEmpty)
    }
}

struct MPImageURLTests {
    @Test func selectsRoleSpecificR2Sibling() throws {
        let source = try #require(URL(string: "https://cdn.masaport.com/listings/uuid/photo-hero.webp"))
        #expect(MPImageURL.variantURL(for: source, role: .thumbnail)?.absoluteString == "https://cdn.masaport.com/listings/uuid/photo-thumb.webp")
        #expect(MPImageURL.variantURL(for: source, role: .card)?.absoluteString == "https://cdn.masaport.com/listings/uuid/photo-card.webp")
        #expect(MPImageURL.variantURL(for: source, role: .detail)?.absoluteString == source.absoluteString)
        #expect(MPImageURL.variantURL(for: source, role: .logo)?.absoluteString == "https://cdn.masaport.com/listings/uuid/photo-thumb.webp")
    }

    @Test func preservesLegacyExternalAndParameterizedURLs() throws {
        let values = [
            "https://cdn.masaport.com/legacy/photo.webp",
            "https://cdn.masaport.com/photo-hero.webp?width=400",
            "https://images.example.com/photo-hero.webp",
            "/images/photo.webp",
        ]
        for value in values {
            let url = try #require(URL(string: value))
            #expect(MPImageURL.variantURL(for: url, role: .card)?.absoluteString == value)
        }
    }
}

struct CustomerAccountTests {
    @Test func decodesProfileFieldsAndToleratesLegacyPayload() throws {
        let full = #"{"id":5,"name":"Ada Lovelace","email":"a@b.co","phone":null,"email_verified":true,"marketing_consent":false,"birth_date":"1990-05-17","preferences":{"dietary":["vegan"],"seating":[]},"created_at":"2026-09-05T11:59:04.239Z"}"#
        let account = try JSONDecoder().decode(CustomerAccount.self, from: Data(full.utf8))
        #expect(account.birthDate == "1990-05-17")
        #expect(account.preferences?.dietary == ["vegan"])
        #expect(account.initials == "AL")
        #expect(account.completionRatio == 0.75)

        let legacy = #"{"id":1,"name":"Misafir","email":"m@b.co","phone":"+905551112233"}"#
        let old = try JSONDecoder().decode(CustomerAccount.self, from: Data(legacy.utf8))
        #expect(old.preferences == nil)
        #expect(old.completionRatio == 0.5)
        #expect(old.initials == "M")
    }

    @Test func updateRequestOmitsUnsetFields() throws {
        let data = try JSONEncoder().encode(UpdateAccountRequest(preferences: CustomerPreferences(dietary: ["halal"], seating: ["window"])))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["name"] == nil)
        #expect(object["birth_date"] == nil)
        #expect((object["preferences"] as? [String: [String]])?["dietary"] == ["halal"])
    }

    @Test func shortCodeUsesUuidTail() {
        #expect(SavedReservation.shortCode(from: "0f8fad5b-d9cb-469f-a165-70867728950e") == "7728950E")
    }

    @Test func deviceSessionSymbolFollowsPlatform() throws {
        let json = #"{"sessions":[{"id":"s1","device":"Chrome · Mac","platform":"desktop","is_current":false,"created_at":"2026-09-05T11:59:04.239Z","last_used_at":null,"expires_at":"2026-11-04T11:59:04.242Z"}]}"#
        let envelope = try JSONDecoder().decode(CustomerDeviceSessionsEnvelope.self, from: Data(json.utf8))
        let session = try #require(envelope.sessions.first)
        #expect(session.symbolName == "desktopcomputer")
        #expect(session.lastUsedDate != nil)
    }

    @Test func webReservationHandoffPrefillsAccountWithoutPuttingPIIInQuery() throws {
        let slot = PublicSlot(
            id: 42,
            startTime: "20:00",
            endTime: "22:00",
            durationMinutes: 120,
            bookingMode: "STANDARD",
            requiresManualApproval: false,
            bookingMessage: nil,
            minimumSpendRequired: false,
            minimumSpendSummary: nil,
            prepaymentRequired: true,
            prepaymentSummary: "Toplam 500 TL",
            prepaymentTotalAmount: APINumber(500)
        )
        let url = AppConfiguration.webReservationURL(
            venueID: 1,
            date: "2026-09-09",
            guestCount: 2,
            slot: slot,
            customerName: "Ada Lovelace",
            customerPhone: "+90 555 111 22 33",
            customerEmail: "ada@example.com",
            note: "Pencere kenarı",
            paymentOnly: true,
            reservationHoldID: 77,
            reservationHoldUUID: "0f8fad5b-d9cb-469f-a165-70867728950e",
            holdExpiresAt: "2026-09-09T17:15:00.000Z"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        let queryNames = Set(queryItems.map(\.name))

        #expect(queryNames.isDisjoint(with: ["customer_name", "customer_phone", "customer_email"]))
        #expect(queryItems.first { $0.name == "guestCount" }?.value == "2")
        #expect(queryItems.first { $0.name == "start_time" }?.value == "20:00")
        #expect(queryItems.first { $0.name == "timeSlotId" }?.value == "42")
        #expect(queryItems.first { $0.name == "payment_only" }?.value == "true")
        #expect(queryItems.first { $0.name == "prepayment_total_amount" }?.value == "500.0")

        var fragmentComponents = URLComponents()
        fragmentComponents.percentEncodedQuery = components.percentEncodedFragment
        let fragmentItems = try #require(fragmentComponents.queryItems)
        #expect(fragmentItems.first { $0.name == "customer_name" }?.value == "Ada Lovelace")
        #expect(fragmentItems.first { $0.name == "customer_phone" }?.value == "+90 555 111 22 33")
        #expect(fragmentItems.first { $0.name == "customer_email" }?.value == "ada@example.com")
        #expect(fragmentItems.first { $0.name == "reservation_note" }?.value == "Pencere kenarı")
        #expect(fragmentItems.first { $0.name == "hold_id" }?.value == "77")
        #expect(fragmentItems.first { $0.name == "hold_uuid" }?.value == "0f8fad5b-d9cb-469f-a165-70867728950e")
        #expect(fragmentItems.first { $0.name == "hold_expires_at" }?.value == "2026-09-09T17:15:00.000Z")
    }
}

struct ReservationQrTests {
    @Test func createResponseCarriesUuidForQr() throws {
        let json = #"{"success":true,"message":"ok","data":{"reservation_id":7,"reservation_uuid":"0f8fad5b-d9cb-469f-a165-70867728950e","reservation_status":"CONFIRMED","start_time":"19:30","requires_payment":false}}"#
        let response = try JSONDecoder().decode(ReservationCreateResponse.self, from: Data(json.utf8))
        #expect(response.data?.reservationUuid == "0f8fad5b-d9cb-469f-a165-70867728950e")
    }

    @Test func paymentStatusCarriesReservationUuid() throws {
        let json = #"{"id":"pay_1","status":"SUCCESS","reservationId":7,"reservationUuid":"0f8fad5b-d9cb-469f-a165-70867728950e"}"#
        let status = try JSONDecoder().decode(PaymentStatus.self, from: Data(json.utf8))
        #expect(status.isSuccess)
        #expect(status.reservationUuid == "0f8fad5b-d9cb-469f-a165-70867728950e")
    }
}

import Foundation
import Testing
@testable import MasaPort

struct ModelDecodingTests {
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

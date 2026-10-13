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
        #expect(AppDeepLink.parse(event)?.route == .eventByID(id: 42))
    }

    @Test func ignoresUnrelatedLinks() throws {
        let url = try #require(URL(string: "https://example.com/restaurant/test-mekan"))
        #expect(AppDeepLink.parse(url) == nil)
    }

    @Test func parsesShortReservationLinkAsListing() throws {
        let plain = try #require(URL(string: "https://masaport.com/r/test-mekan"))
        let parsed = try #require(AppDeepLink.parse(plain))
        #expect(parsed == .listing(slug: "test-mekan", prefill: BookingPrefill()))
        #expect(parsed.tab == .restaurants)
        #expect(parsed.route == .listing(slug: "test-mekan", prefill: BookingPrefill()))

        let day = try #require(Calendar.istanbul.date(byAdding: .day, value: 2, to: Calendar.istanbul.startOfDay(for: .now)))
        let dayString = DateFormat.apiDay.string(from: day)
        let prefilled = try #require(URL(string: "https://www.masaport.com/r/test-mekan?date=\(dayString)&time=20:30&guests=4&utm_source=qr"))
        #expect(AppDeepLink.parse(prefilled) == .listing(slug: "test-mekan", prefill: BookingPrefill(date: day, time: "20:30", guests: 4)))
    }

    @Test func shortReservationLinkIgnoresInvalidPrefill() throws {
        let url = try #require(URL(string: "https://masaport.com/r/test-mekan?date=2020-01-01&time=25:00&guests=40"))
        #expect(AppDeepLink.parse(url) == .listing(slug: "test-mekan", prefill: BookingPrefill()))

        let farFuture = try #require(Calendar.istanbul.date(byAdding: .day, value: 30, to: .now))
        let items = [
            URLQueryItem(name: "date", value: DateFormat.apiDay.string(from: farFuture)),
            URLQueryItem(name: "time", value: "9:5"),
            URLQueryItem(name: "guests", value: "0"),
        ]
        #expect(BookingPrefill(queryItems: items) == BookingPrefill())
    }

    @Test func emptySlugsDoNotProduceRoutes() throws {
        let values = [
            "https://masaport.com/istanbul/restoranlar/",
            "https://masaport.com/istanbul/restoranlar",
            "https://masaport.com/etkinlikler/",
            "https://masaport.com/istanbul/etkinlikler/",
            "https://masaport.com/restaurant/",
            "https://masaport.com/r/",
            "https://masaport.com/r/%20",
            "https://masaport.com/etkinlikler/%20/",
            "masaport://restaurant",
            "masaport://event/",
            "https://masaport.com/",
        ]
        for value in values {
            let url = try #require(URL(string: value))
            #expect(AppDeepLink.parse(url) == nil, "\(value) rota üretmemeli")
        }
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

    @Test func decodesSingleEnvelopeHandoffAsCreated() throws {
        // `APIClient` dış zarfı açtıktan sonra kalan nesne: `data` anahtarı yoktur.
        let inner = #"{"requires_payment":true,"amount":500,"reservationHoldId":77,"reservationHoldUuid":"0f8fad5b-d9cb-469f-a165-70867728950e","holdExpiresAt":"2026-09-09T17:15:00.000Z"}"#
        let response = try JSONDecoder().decode(ReservationCreateResponse.self, from: Data(inner.utf8))
        #expect(response.data?.reservationHoldId == 77)
        #expect(response.data?.requiresPayment == true)

        let empty = try JSONDecoder().decode(ReservationCreateResponse.self, from: Data(#"{"success":true,"data":null}"#.utf8))
        #expect(empty.data == nil)
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

    @Test func dateSpecificRuleOverridesWeekdayTemplate() throws {
        let date = try #require(DateFormat.parseAPIDay("2026-10-16")) // Cuma
        let availability = try JSONDecoder().decode(VenueAvailability.self, from: Data(Fixtures.availability(date: "2026-10-16", rule: Fixtures.preauthRule).utf8))
        let option = try #require(availability.slotOptions(for: date).first)

        // Haftalık şablon ön ödeme istemiyor; o tarihin kuralı (caz gecesi) kart provizyonu istiyor.
        #expect(availability.slots?["5"]?.first?.prepaymentRequired == false)
        #expect(option.slot.requiresPrepayment)
        #expect(option.slot.isPreauth)
        #expect(option.slot.prepaymentTotal == 500)
        #expect(option.slot.prepaymentSummary == "Kişi başı 250 TL kart provizyonu")
        #expect(option.slot.prepaymentMode == "PER_GUEST")
        #expect(option.slot.endTime == "23:30")
        #expect(option.caption == "Kart provizyonu")
        #expect(option.isBookable)
    }

    @Test func templateIsUsedWhenDateCarriesNoRule() throws {
        let date = try #require(DateFormat.parseAPIDay("2026-10-16"))
        let legacyStatus = #"{"is_full":false,"is_blocked":false,"is_blocked_by_time":false,"available_guest_capacity":12,"available_tables":3}"#
        let availability = try JSONDecoder().decode(VenueAvailability.self, from: Data(Fixtures.availability(date: "2026-10-16", rule: legacyStatus).utf8))
        let option = try #require(availability.slotOptions(for: date).first)
        #expect(!option.slot.requiresPrepayment)
        #expect(option.slot.endTime == "23:00")
        #expect(option.caption == nil)
    }

    @Test func requestOnlyRuleOnDateWinsOverPrepaymentBadge() throws {
        let date = try #require(DateFormat.parseAPIDay("2026-10-16"))
        let rule = #"{"is_full":false,"is_blocked":false,"booking_mode":"REQUEST_ONLY","requires_manual_approval":true,"booking_message":"Özel gece; mekan onaylar.","prepayment_required":true,"prepayment_capture_mode":"CHARGE","prepayment_total_amount":0}"#
        let availability = try JSONDecoder().decode(VenueAvailability.self, from: Data(Fixtures.availability(date: "2026-10-16", rule: rule).utf8))
        let option = try #require(availability.slotOptions(for: date).first)
        #expect(option.slot.isRequestOnly)
        #expect(option.slot.bookingMessage == "Özel gece; mekan onaylar.")
        #expect(option.caption == "Onaylı")
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

    @Test func webHandoffCarriesCaptureModeAndDateRule() throws {
        let date = try #require(DateFormat.parseAPIDay("2026-10-16"))
        let availability = try JSONDecoder().decode(VenueAvailability.self, from: Data(Fixtures.availability(date: "2026-10-16", rule: Fixtures.preauthRule).utf8))
        let slot = try #require(availability.slotOptions(for: date).first?.slot)
        let url = AppConfiguration.webReservationURL(venueID: 100, date: "2026-10-16", guestCount: 2, slot: slot, paymentOnly: true)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(value("prepayment_capture_mode") == "PREAUTH")
        #expect(value("prepayment_required") == "true")
        #expect(value("prepayment_total_amount") == "500.0")
        #expect(value("prepayment_amount") == "250.0")
        #expect(value("prepayment_mode") == "PER_GUEST")
        #expect(value("prepayment_summary") == "Kişi başı 250 TL kart provizyonu")
        #expect(value("end_time") == "23:30")
    }

    @Test func chargeSlotSendsChargeCaptureMode() throws {
        let slot = PublicSlot(id: 1, startTime: "20:00", endTime: "22:00", durationMinutes: 120, bookingMode: "STANDARD", requiresManualApproval: false, bookingMessage: nil, minimumSpendRequired: false, minimumSpendSummary: nil, prepaymentRequired: true, prepaymentSummary: "Kişi başı 500 TL", prepaymentTotalAmount: APINumber(1000), prepaymentCaptureMode: "CHARGE")
        let url = AppConfiguration.webReservationURL(venueID: 1, date: "2026-10-16", guestCount: 2, slot: slot)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "prepayment_capture_mode" }?.value == "CHARGE")
        #expect(!slot.isPreauth)
        #expect(slot.prepaymentTitle == "Ön ödeme")
    }
}

struct ReservationManagementTests {
    @Test func decodesManagementUrlFromAccountList() throws {
        let json = #"""
        {"reservations":[{"kind":"restaurant","id":9001,"uuid":"8b9f1c2e-4d6a-4f3b-9a1e-2c7d5e6f7a80","status":"CONFIRMED","reservation_date":"2099-10-14","start_time":"20:00","end_time":"22:00","guest_count":4,"note":null,"checked_in":false,"created_at":"2026-10-01T09:00:00.000Z","customer_name":"Ada","management_url":"https://app.masaport.com/public/reservation/manage/8b9f1c2e-4d6a-4f3b-9a1e-2c7d5e6f7a80#token=abc.def-ghi","venue":{"id":100,"name":"Moda","listing_slug":"moda"}},
         {"kind":"restaurant","id":9002,"uuid":"1b9f1c2e-4d6a-4f3b-9a1e-2c7d5e6f7a81","status":"CANCELLED","reservation_date":"2099-10-15","start_time":"20:00","guest_count":2,"checked_in":false,"management_url":null,"venue":{"id":100,"name":"Moda"}},
         {"kind":"event","id":51,"uuid":"2b9f1c2e-4d6a-4f3b-9a1e-2c7d5e6f7a82","status":"CONFIRMED","start_datetime":"2099-10-16T18:00:00.000Z","guest_count":2,"checked_in":false,"event":{"id":101,"title":"Caz"}}]}
        """#
        let envelope = try JSONDecoder().decode(CustomerReservationsEnvelope.self, from: Data(json.utf8))
        let saved = envelope.reservations.compactMap { $0.asSavedReservation() }
        #expect(saved.count == 3)

        let upcoming = saved[0]
        #expect(upcoming.managementURL?.hasPrefix("https://app.masaport.com/public/reservation/manage/") == true)
        #expect(upcoming.managementLink != nil)
        #expect(upcoming.managementToken == "abc.def-ghi")
        #expect(upcoming.checkedIn == false)

        #expect(saved[1].isCancelled)
        #expect(saved[1].managementLink == nil)
        // Etkinlik kayıtlarında yönetim bağlantısı yoktur.
        #expect(saved[2].kind == .event)
        #expect(saved[2].managementLink == nil)
    }

    @Test func managementLinkHiddenForPastCheckedInOrEventBookings() {
        let link = "https://app.masaport.com/public/reservation/manage/x#token=t"
        var reservation = Fixtures.savedReservation(managementURL: link)
        #expect(reservation.managementLink != nil)

        reservation.checkedIn = true
        #expect(reservation.managementLink == nil)

        reservation = Fixtures.savedReservation(managementURL: link, start: .now.addingTimeInterval(-86_400))
        #expect(reservation.managementLink == nil)

        reservation = Fixtures.savedReservation(managementURL: link, kind: .event)
        #expect(reservation.managementLink == nil)

        reservation = Fixtures.savedReservation(managementURL: "javascript:alert(1)")
        #expect(reservation.managementLink == nil)
    }

    @Test func decodesReservationsSavedByOlderVersions() throws {
        // Önceki sürümün yazdığı dosya: managementURL ve checkedIn alanları yok.
        let legacy = #"""
        [{"id":"5F2A7C3E-9B1D-4E6F-8A2B-3C4D5E6F7A80","kind":"restaurant","remoteId":7,"remoteUUID":"0f8fad5b-d9cb-469f-a165-70867728950e","title":"Moda Balıkçısı","subtitle":"Balık · Kadıköy","image":null,"startDate":3000000000,"endDate":3000007200,"timeText":"20:00","guestCount":2,"status":"CONFIRMED","customerName":"Ada","note":null,"venueId":100,"listingSlug":"moda-balikcisi","eventId":null,"address":null,"phone":"+902165550001","latitude":40.97,"longitude":29.02,"createdAt":780000000}]
        """#
        let decoded = try JSONDecoder().decode([SavedReservation].self, from: Data(legacy.utf8))
        let reservation = try #require(decoded.first)
        #expect(reservation.managementURL == nil)
        #expect(reservation.checkedIn == nil)
        #expect(reservation.managementLink == nil)
        #expect(reservation.remoteId == 7)

        // Yeni alanlar kaydedilip geri okunabilir.
        var updated = reservation
        updated.managementURL = "https://app.masaport.com/public/reservation/manage/0f8fad5b#token=abc"
        let roundTrip = try JSONDecoder().decode(SavedReservation.self, from: JSONEncoder().encode(updated))
        #expect(roundTrip.managementURL == updated.managementURL)
    }

    @Test @MainActor func storeLoadsLegacyFileAndRefreshesFromServer() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "masaport-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = #"[{"id":"5F2A7C3E-9B1D-4E6F-8A2B-3C4D5E6F7A80","kind":"restaurant","remoteId":7,"remoteUUID":"0F8FAD5B-D9CB-469F-A165-70867728950E","title":"Moda","startDate":4000000000,"timeText":"20:00","guestCount":2,"status":"CONFIRMED","customerName":"Ada","createdAt":780000000}]"#
        try Data(legacy.utf8).write(to: directory.appending(path: "reservations.json"))

        let store = MyReservationsStore(directory: directory)
        #expect(store.reservations.count == 1)

        var server = Fixtures.savedReservation(managementURL: nil, start: Date(timeIntervalSinceReferenceDate: 4_000_000_000))
        server.status = "CANCELLED"
        store.refresh(with: server)
        #expect(store.reservations.first?.isCancelled == true)
        #expect(MyReservationsStore(directory: directory).reservations.first?.status == "CANCELLED")
    }

    @Test func guestManagementResponseUpdatesLocalCopy() {
        let reservation = Fixtures.savedReservation(managementURL: "https://app.masaport.com/public/reservation/manage/x#token=t")
        let cancelled = reservation.applying(GuestManagedReservation(uuid: "x", reservationDate: nil, startTime: nil, endTime: nil, guestCount: nil, status: "CANCELLED"))
        #expect(cancelled.isCancelled)
        #expect(cancelled.managementURL == nil)

        let moved = reservation.applying(GuestManagedReservation(uuid: "x", reservationDate: "2099-01-02", startTime: "21:30", endTime: "23:30", guestCount: 5, status: "CONFIRMED"))
        #expect(moved.timeText == "21:30")
        #expect(moved.guestCount == 5)
        #expect(DateFormat.apiDay.string(from: moved.startDate) == "2099-01-02")
        #expect(moved.managementLink != nil)
    }
}

struct EventTicketTests {
    @Test func encodesTicketOptionOnlyWhenSelected() throws {
        var request = EventReservationRequest(contactName: "Ada", contactEmail: "a@b.co", contactPhone: nil, guestCount: 2, participants: nil, notes: nil, couponCode: nil)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["ticket_option_id"] == nil)

        request.ticketOptionId = "balkon"
        object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["ticket_option_id"] as? String == "balkon")
        #expect(object["guest_count"] as? Int == 2)
    }

    @Test func decodesTicketConfigAndInstanceStock() throws {
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(Fixtures.ticketEvent.utf8))
        let instance = try #require(event.upcomingInstances.first)
        let choices = event.ticketChoices(for: instance)

        #expect(event.requiresTicketOption)
        // Satışa kapalı VIP gösterilmez.
        #expect(choices.map(\.id) == ["standart", "ogrenci", "davetiye"])
        #expect(choices[0].sectionName == "Salon")
        #expect(choices[0].unitPrice == 450)
        #expect(choices[0].available == nil)
        #expect(choices[1].isSoldOut)
        #expect(choices[2].isFree)
        #expect(choices[2].isLowStock)
        // Başlangıç fiyatı 0 olsa da tüm biletler ücretsiz değildir.
        #expect(!event.isFree)
        #expect(event.offersFreeTicket)
        #expect(event.lowestPaidPrice == 300)
        #expect(!event.isSoldOut(instance))
    }

    @Test func trialVenueTicketsAreFree() throws {
        let json = Fixtures.ticketEvent.replacingOccurrences(of: #""paymentType":"FULL""#, with: #""paymentType":"NONE""#)
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(json.utf8))
        #expect(event.isFree)
        #expect(event.saleableTicketOptions.allSatisfy { $0.unitPrice == 0 })
    }

    @Test @MainActor func ticketSelectionDrivesPriceAndPaymentPath() throws {
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(Fixtures.ticketEvent.utf8))
        let instance = try #require(event.upcomingInstances.first)
        let viewModel = EventReservationViewModel(event: event, instance: instance, preferences: Fixtures.preferences(), canPayInApp: false)
        #expect(viewModel.selectedTicket == nil)
        #expect(!viewModel.canSubmit)

        let standard = try #require(viewModel.ticketChoices.first { $0.id == "standart" })
        viewModel.selectTicket(standard)
        viewModel.guestCount = 2
        #expect(viewModel.totalAmount == 900)
        #expect(viewModel.requiresPayment)
        #expect(viewModel.needsWebPayment)
        #expect(viewModel.canSubmit)

        let soldOut = try #require(viewModel.ticketChoices.first { $0.id == "ogrenci" })
        viewModel.selectTicket(soldOut)
        #expect(viewModel.selectedTicketID == "standart")

        let invitation = try #require(viewModel.ticketChoices.first { $0.id == "davetiye" })
        viewModel.guestCount = 6
        viewModel.selectTicket(invitation)
        #expect(viewModel.guestCount == 4) // davetiyede 4 yer kaldı
        #expect(!viewModel.requiresPayment)
        #expect(!viewModel.needsWebPayment)
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

// MARK: - Test verileri

enum Fixtures {
    static let preauthRule = #"{"start_time":"21:00","end_time":"23:30","duration_minutes":150,"is_full":false,"is_blocked":false,"is_blocked_by_time":false,"available_guest_capacity":12,"available_tables":3,"booking_mode":"STANDARD","requires_manual_approval":false,"booking_message":null,"minimum_spend_required":false,"minimum_spend_amount":0,"minimum_spend_summary":null,"prepayment_required":true,"prepayment_mode":"PER_GUEST","prepayment_amount":250,"prepayment_total_amount":"500.00","prepayment_summary":"Kişi başı 250 TL kart provizyonu","prepayment_capture_mode":"PREAUTH","effective_rule_id":7,"effective_rule_name":"Caz gecesi"}"#

    /// `GET /venues/public/:id` cevabı: her gün aynı 21:00 şablonu, verilen tarihte `rule`.
    static func availability(date: String, rule: String) -> String {
        let slot = #"{"id":1001,"start_time":"21:00","end_time":"23:00","duration_minutes":120,"booking_mode":"STANDARD","requires_manual_approval":false,"booking_message":null,"minimum_spend_required":false,"minimum_spend_amount":0,"minimum_spend_summary":null,"prepayment_required":false,"prepayment_mode":"DEFAULT","prepayment_amount":0,"prepayment_total_amount":0,"prepayment_summary":null,"prepayment_capture_mode":"CHARGE"}"#
        let days = (1...7).map { #""\#($0)":[\#(slot)]"# }.joined(separator: ",")
        return #"{"id":100,"name":"Moda","timezone":"Europe/Istanbul","texts":[],"slots":{\#(days)},"blocked_dates":[],"availability":{"\#(date)":{"is_blocked":false,"is_day_full":false,"slots":{"1001":\#(rule)}}},"isSubscriptionActive":true}"#
    }

    /// `GET /events/:id/public`: bilet seçenekli, ödeme alan etkinlik (başlangıç fiyatı 0).
    static let ticketEvent = #"""
    {"id":101,"slug":"caz","title":"Caz Gecesi","pricePerPerson":"0","paymentType":"FULL","maxCapacity":60,
     "ticketConfig":{"sections":[{"id":"salon","name":"Salon","capacity":40}],
       "options":[{"id":"standart","ticketType":"Standart","category":"Tam","sectionId":"salon","price":450,"capacity":null,"active":true},
                  {"id":"ogrenci","ticketType":"Öğrenci","category":"İndirimli","sectionId":"salon","price":300,"capacity":10,"active":true},
                  {"id":"davetiye","ticketType":"Davetiye","category":"","sectionId":null,"price":0,"capacity":15,"active":true},
                  {"id":"vip","ticketType":"VIP","category":"Sahne önü","sectionId":null,"price":1200,"capacity":6,"active":false}]},
     "instances":[{"id":1010,"start_datetime":"2099-10-16T18:00:00.000Z","end_datetime":"2099-10-16T21:00:00.000Z","max_capacity":60,"total_reserved":10,"available_spots":50,
       "ticket_availability":[{"optionId":"standart","available":null},{"optionId":"ogrenci","available":0},{"optionId":"davetiye","available":4},{"optionId":"vip","available":0}]}]}
    """#

    @MainActor static func preferences() -> PreferencesStore {
        PreferencesStore(defaults: UserDefaults(suiteName: "MasaPortTests-\(UUID().uuidString)")!)
    }

    static func savedReservation(managementURL: String?, kind: SavedReservation.Kind = .restaurant, start: Date = .now.addingTimeInterval(2 * 86_400)) -> SavedReservation {
        SavedReservation(
            id: UUID(), kind: kind, remoteId: 7, remoteUUID: "0f8fad5b-d9cb-469f-a165-70867728950e", title: "Moda", subtitle: nil, image: nil,
            startDate: start, endDate: nil, timeText: "20:00", guestCount: 2, status: "CONFIRMED", customerName: "Ada", note: nil,
            venueId: 100, listingSlug: "moda", eventId: nil, address: nil, phone: nil, latitude: nil, longitude: nil, createdAt: .now,
            managementURL: managementURL
        )
    }
}

@MainActor
struct FavoritesSyncTests {
    private func makeStore() -> FavoritesStore {
        FavoritesStore(directory: FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString)"))
    }

    private func item(_ id: Int) -> FavoritesStore.Item {
        .init(kind: .listing, remoteId: id, title: "Mekân \(id)", subtitle: nil, image: nil, slug: "mekan-\(id)", addedAt: .now)
    }

    private func remote(_ id: Int) throws -> CustomerFavorite {
        let json = #"{"kind":"listing","id":\#(id),"slug":"mekan-\#(id)","title":"Mekân \#(id)","subtitle":null,"image":null,"added_at":null}"#
        return try JSONDecoder().decode(CustomerFavorite.self, from: Data(json.utf8))
    }

    @Test func anonymousChangesStayLocalUntilFirstSync() {
        let store = makeStore()
        store.toggle(item(1))
        #expect(store.pendingChanges.isEmpty)
        #expect(store.isFavorite(listing: 1))
    }

    @Test func serverListWinsButUnsentChangesAreKept() throws {
        let store = makeStore()
        store.markSynced(accountId: 7)
        store.toggle(item(3))          // eklendi, gönderilemedi
        store.replace(with: [try remote(1), try remote(2)])
        store.remove(id: "listing-1")  // silindi, gönderilemedi
        store.replace(with: [try remote(1), try remote(2)])
        #expect(store.isFavorite(listing: 3))
        #expect(!store.isFavorite(listing: 1))
        #expect(store.isFavorite(listing: 2))
        #expect(store.pendingChanges.count == 2)
    }

    @Test func signingOutClearsAccountFavorites() throws {
        let store = makeStore()
        store.markSynced(accountId: 7)
        store.replace(with: [try remote(1)])
        store.toggle(item(2))
        store.resetForSignedOut()
        #expect(store.items.isEmpty)
        #expect(store.pendingChanges.isEmpty)
        #expect(store.syncedAccountId == nil)
    }
}

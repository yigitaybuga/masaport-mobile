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

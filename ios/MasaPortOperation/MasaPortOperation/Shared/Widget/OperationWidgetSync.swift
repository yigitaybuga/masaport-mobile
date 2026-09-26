import Foundation
import WidgetKit

enum OperationWidgetSync {
    static func update(
        venue: Venue,
        reservations: [Reservation],
        tables: [VenueTable],
        waitlist: [WaitlistEntry],
        referenceDate: Date = .now
    ) {
        let snapshot = makeSnapshot(
            venue: venue,
            reservations: reservations,
            tables: tables,
            waitlist: waitlist,
            referenceDate: referenceDate
        )
        guard OperationWidgetSnapshotStore.save(snapshot) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: OperationWidgetConfiguration.kind)
    }

    static func clear() {
        OperationWidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: OperationWidgetConfiguration.kind)
    }

    static func makeSnapshot(
        venue: Venue,
        reservations: [Reservation],
        tables: [VenueTable],
        waitlist: [WaitlistEntry],
        referenceDate: Date = .now
    ) -> OperationWidgetSnapshot {
        let nextReservation = reservations
            .compactMap { reservation -> (reservation: Reservation, date: Date)? in
                guard !reservation.checkedIn,
                      reservation.operationalState(relativeTo: referenceDate) != .terminal,
                      let date = reservation.startDate(),
                      date >= referenceDate else {
                    return nil
                }
                return (reservation, date)
            }
            .min { $0.date < $1.date }?
            .reservation

        return OperationWidgetSnapshot(
            venueName: venue.name,
            generatedAt: referenceDate,
            reservationCount: reservations.count,
            activeTableCount: tables.count { table in
                guard let status = table.serviceStatus?.uppercased() else { return false }
                return !["EMPTY", "LEFT", "CLEANING"].contains(status)
            },
            waitlistCount: waitlist.count,
            overdueCount: reservations.count { reservation in
                if case .overdue = reservation.operationalState(relativeTo: referenceDate) {
                    return true
                }
                return false
            },
            pendingCount: reservations.count { $0.status.uppercased() == "PENDING" },
            nextReservation: nextReservation.map {
                OperationWidgetReservation(
                    startTime: String($0.startTime.prefix(5)),
                    guestCount: $0.guestCount
                )
            },
            tableCount: tables.count,
            arrivedCount: reservations.count { $0.checkedIn },
            expectedCount: reservations.count { $0.checkedIn || $0.status.uppercased() == "CONFIRMED" },
            insideCount: reservations.count { reservation in
                if case .inside = reservation.operationalState(relativeTo: referenceDate) { return true }
                return false
            }
        )
    }
}

import Foundation

struct OperationWidgetSnapshot: Codable, Equatable {
    let venueName: String
    let generatedAt: Date
    let reservationCount: Int
    let activeTableCount: Int
    let waitlistCount: Int
    let overdueCount: Int
    let pendingCount: Int
    let nextReservation: OperationWidgetReservation?

    static let placeholder = OperationWidgetSnapshot(
        venueName: "MasaPort",
        generatedAt: .now,
        reservationCount: 18,
        activeTableCount: 7,
        waitlistCount: 3,
        overdueCount: 1,
        pendingCount: 2,
        nextReservation: OperationWidgetReservation(startTime: "19:30", guestCount: 4)
    )

    static let empty = OperationWidgetSnapshot(
        venueName: "MasaPort",
        generatedAt: .now,
        reservationCount: 0,
        activeTableCount: 0,
        waitlistCount: 0,
        overdueCount: 0,
        pendingCount: 0,
        nextReservation: nil
    )
}

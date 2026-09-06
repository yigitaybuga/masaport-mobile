import EventKit
import Foundation

/// Rezervasyonu cihaz takvimine yalnızca yazma izniyle ekler.
enum CalendarExport {
    enum Outcome { case added, denied, failed }

    static func add(_ reservation: SavedReservation) async -> Outcome {
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return .denied }
            let event = EKEvent(eventStore: store)
            event.title = reservation.kind == .restaurant ? "\(reservation.title) rezervasyonu" : reservation.title
            event.startDate = reservation.startDate
            event.endDate = reservation.endDate ?? reservation.startDate.addingTimeInterval(2 * 3600)
            event.location = reservation.address ?? reservation.subtitle
            event.notes = ["MasaPort · \(Format.guests(reservation.guestCount))", reservation.note].compactMap { $0 }.joined(separator: "\n")
            event.calendar = store.defaultCalendarForNewEvents
            event.addAlarm(EKAlarm(relativeOffset: -3600))
            try store.save(event, span: .thisEvent)
            return .added
        } catch {
            return .failed
        }
    }
}

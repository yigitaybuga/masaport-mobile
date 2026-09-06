import Foundation
import Combine

@MainActor
final class EventsViewModel: ObservableObject {
    @Published private(set) var events: [EventSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(venueID: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            events = try await api.get("/events/\(venueID)/events?per_page=100")
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Etkinlikler yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    var grouped: [(phase: EventPhase, events: [EventSummary])] {
        let now = Date.now
        let buckets = Dictionary(grouping: events) { $0.phase(relativeTo: now) }
        return buckets.keys.sorted().map { phase in
            let sorted = buckets[phase, default: []].sorted { lhs, rhs in
                let left = lhs.displayedInstance?.startDate ?? EventDates.parse(lhs.startDatetime) ?? .distantPast
                let right = rhs.displayedInstance?.startDate ?? EventDates.parse(rhs.startDatetime) ?? .distantPast
                return phase == .past ? left > right : left < right
            }
            return (phase, sorted)
        }
    }
}

@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published private(set) var reservations: [EventReservation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var checkingInID: Int?
    @Published private(set) var errorMessage: String?
    @Published private(set) var successCount = 0

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(venueID: Int, eventID: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            reservations = try await api.get("/events/\(venueID)/reservations/\(eventID)")
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Katılımcılar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    func checkIn(_ reservation: EventReservation, venueID: Int, eventID: Int) async -> Bool {
        guard let uuid = reservation.uuid else { return false }
        checkingInID = reservation.id
        errorMessage = nil
        defer { checkingInID = nil }
        do {
            let payload: CheckinPayload<CheckinResult> = try await api.post("/checkin/event/\(uuid)")
            guard payload.success else {
                errorMessage = payload.error ?? payload.message ?? "Check-in tamamlanamadı."
                return false
            }
            successCount += 1
            await load(venueID: venueID, eventID: eventID)
            return true
        } catch let error as APIError {
            errorMessage = error.detail ?? error.message
            await load(venueID: venueID, eventID: eventID)
            return false
        } catch {
            errorMessage = "Check-in tamamlanamadı. Tekrar deneyin."
            return false
        }
    }
}

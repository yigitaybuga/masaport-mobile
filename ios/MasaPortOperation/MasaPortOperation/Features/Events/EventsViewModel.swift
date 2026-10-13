import Foundation
import Combine

@MainActor
final class EventsViewModel: ObservableObject {
    @Published private(set) var events: [EventSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let api: APIClient
    private var loadGate = LoadGate()

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// `silent`: ön plana dönüş ve düzenli yenileme; boş listede yükleniyor/boş durum arasında gidip gelmez.
    func load(venueID: Int, silent: Bool = false) async {
        guard let generation = loadGate.begin(silent: silent) else { return }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        defer {
            if loadGate.isCurrent(generation) { isLoading = false }
            loadGate.end(generation)
        }
        do {
            let loaded: [EventSummary] = try await api.get("/events/\(venueID)/events?per_page=100")
            guard loadGate.isCurrent(generation) else { return }
            events = loaded
            errorMessage = nil
        } catch let error as APIError {
            guard loadGate.isCurrent(generation) else { return }
            errorMessage = error.message
        } catch {
            guard loadGate.isCurrent(generation), !error.isCancellation else { return }
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
    private var loadGate = LoadGate()

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// `silent`: kapıda başka cihazlardan yapılan check-in'leri yansıtan arka plan tazelemesi.
    func load(venueID: Int, eventID: Int, silent: Bool = false) async {
        guard let generation = loadGate.begin(silent: silent) else { return }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        defer {
            if loadGate.isCurrent(generation) { isLoading = false }
            loadGate.end(generation)
        }
        do {
            let loaded: [EventReservation] = try await api.get("/events/\(venueID)/reservations/\(eventID)")
            guard loadGate.isCurrent(generation) else { return }
            reservations = loaded
            errorMessage = nil
        } catch let error as APIError {
            guard loadGate.isCurrent(generation) else { return }
            errorMessage = error.message
        } catch {
            guard loadGate.isCurrent(generation), !error.isCancellation else { return }
            errorMessage = "Katılımcılar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    func updateNote(_ reservation: EventReservation, note: String, venueID: Int, eventID: Int) async -> Bool {
        checkingInID = reservation.id
        errorMessage = nil
        defer { checkingInID = nil }
        do {
            let _: EventReservationNoteResult = try await api.put(
                "/events/\(venueID)/reservations/\(eventID)/\(reservation.id)/note",
                body: EventReservationNoteRequest(note: note)
            )
            successCount += 1
            await load(venueID: venueID, eventID: eventID)
            return true
        } catch let error as APIError {
            errorMessage = error.detail ?? error.message
            return false
        } catch {
            errorMessage = "Not kaydedilemedi. Tekrar deneyin."
            return false
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
            // Yeniden yükleme hata bildirimini sıfırlar; mesaj yüklemeden sonra yazılır.
            await load(venueID: venueID, eventID: eventID)
            errorMessage = error.detail ?? error.message
            return false
        } catch {
            errorMessage = "Check-in tamamlanamadı. Tekrar deneyin."
            return false
        }
    }
}

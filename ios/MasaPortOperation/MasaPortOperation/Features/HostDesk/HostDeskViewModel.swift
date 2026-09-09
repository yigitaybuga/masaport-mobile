import Foundation

struct TableAssignmentUpdateRequest: Encodable {
    let tableIDs: [Int]
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case tableIDs = "table_ids"
        case expectedUpdatedAt = "expected_updated_at"
    }
}

struct ServiceStatusUpdateRequest: Encodable {
    let serviceStatus: String
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case serviceStatus = "service_status"
        case expectedUpdatedAt = "expected_updated_at"
    }
}

enum CheckInOutcome: Equatable {
    case completed
    case earlyCheckInRequired(message: String)
    case failed
}

@MainActor
final class HostDeskViewModel: ObservableObject {
    @Published private(set) var reservations: [Reservation] = []
    @Published private(set) var tables: [VenueTable] = []
    @Published private(set) var isLoading = false
    @Published private(set) var checkingInReservationID: Int?
    @Published private(set) var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(venueID: Int, date: Date = .now) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedReservations: [Reservation] = api.get(
                "/reservations/\(venueID)?date=\(OperationDate.apiString(date))&per_page=250&sort_by=startTime&sort_order=asc"
            )
            async let loadedTables: [VenueTable] = api.get("/tables/\(venueID)")
            (reservations, tables) = try await (loadedReservations, loadedTables)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Host Masası güncellenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    /// Sürükle-bırak ile masayı değiştirir; mevcut atama tek masayla değiştirilir.
    func assignTable(_ reservation: Reservation, to table: VenueTable, venueID: Int, date: Date = .now) async -> Bool {
        checkingInReservationID = reservation.id
        errorMessage = nil
        defer { checkingInReservationID = nil }

        do {
            let _: ReservationTableAssignment = try await api.put(
                "/reservations/\(venueID)/\(reservation.id)/tables",
                body: TableAssignmentUpdateRequest(tableIDs: [table.id], expectedUpdatedAt: reservation.updatedAt)
            )
            await load(venueID: venueID, date: date)
            return true
        } catch let error as APIError {
            errorMessage = error.isConflict
                ? "Bu rezervasyon başka bir cihazda değişti. Güncel liste yüklendi."
                : (error.detail ?? error.message)
            await load(venueID: venueID, date: date)
            return false
        } catch {
            errorMessage = "Masa değiştirilemedi. Tekrar denemeden önce listeyi yenileyin."
            return false
        }
    }

    func updateServiceStatus(_ reservation: Reservation, to action: ServiceAction, venueID: Int, date: Date = .now) async -> Bool {
        checkingInReservationID = reservation.id
        errorMessage = nil
        defer { checkingInReservationID = nil }

        do {
            let _: ReservationServiceStatusUpdate = try await api.put(
                "/reservations/\(venueID)/\(reservation.id)/service-status",
                body: ServiceStatusUpdateRequest(serviceStatus: action.rawValue, expectedUpdatedAt: reservation.updatedAt)
            )
            await load(venueID: venueID, date: date)
            return true
        } catch let error as APIError {
            errorMessage = error.isConflict
                ? "Bu rezervasyon başka bir cihazda değişti. Güncel liste yüklendi."
                : (error.detail ?? error.message)
            await load(venueID: venueID, date: date)
            return false
        } catch {
            errorMessage = "Servis durumu güncellenemedi. Tekrar denemeden önce listeyi yenileyin."
            return false
        }
    }

    func checkIn(_ reservation: Reservation, venueID: Int, date: Date = .now, force: Bool = false) async -> CheckInOutcome {
        checkingInReservationID = reservation.id
        errorMessage = nil
        defer { checkingInReservationID = nil }

        do {
            let _: EmptyResponse = try await api.post(
                "/checkin/restaurant/\(reservation.uuid)",
                body: RestaurantCheckinRequest(forceCheckIn: force ? true : nil, expectedUpdatedAt: reservation.updatedAt)
            )
            await load(venueID: venueID, date: date)
            return .completed
        } catch let error as APIError {
            if error.isEarlyCheckInWarning {
                return .earlyCheckInRequired(
                    message: error.detail ?? "Rezervasyon saati henüz gelmedi. Erken check-in yapmak istiyor musunuz?"
                )
            }
            errorMessage = error.isConflict
                ? "Bu rezervasyon başka bir cihazda değişti. Güncel liste yüklendi."
                : (error.detail ?? error.message)
            await load(venueID: venueID, date: date)
            return .failed
        } catch {
            errorMessage = "Check-in tamamlanamadı. Tekrar denemeden önce listeyi yenileyin."
            return .failed
        }
    }

}

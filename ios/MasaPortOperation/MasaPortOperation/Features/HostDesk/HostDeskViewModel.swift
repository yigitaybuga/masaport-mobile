import Foundation

enum CheckInOutcome: Equatable {
    case completed
    case earlyCheckInRequired(message: String)
    case failed
}

@MainActor
final class HostDeskViewModel: ObservableObject {
    @Published private(set) var reservations: [Reservation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var checkingInReservationID: Int?
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
            reservations = try await api.get(
                "/reservations/\(venueID)?date=\(Self.todayString())&per_page=250&sort_by=startTime&sort_order=asc"
            )
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Host Masası güncellenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    func checkIn(_ reservation: Reservation, venueID: Int, force: Bool = false) async -> CheckInOutcome {
        checkingInReservationID = reservation.id
        errorMessage = nil
        defer { checkingInReservationID = nil }

        do {
            let _: EmptyResponse = try await api.post(
                "/checkin/restaurant/\(reservation.uuid)",
                body: RestaurantCheckinRequest(forceCheckIn: force ? true : nil, expectedUpdatedAt: reservation.updatedAt)
            )
            await load(venueID: venueID)
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
            await load(venueID: venueID)
            return .failed
        } catch {
            errorMessage = "Check-in tamamlanamadı. Tekrar denemeden önce listeyi yenileyin."
            return .failed
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

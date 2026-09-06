import Foundation
import Combine

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var reservations: [Reservation] = []
    @Published private(set) var tables: [VenueTable] = []
    @Published private(set) var waitlist: [WaitlistEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(venue: Venue) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let today = Self.todayString()
        do {
            async let reservations: [Reservation] = api.get("/reservations/\(venue.id)?date=\(today)&per_page=250&sort_by=startTime&sort_order=asc")
            async let tables: [VenueTable] = api.get("/tables/\(venue.id)")
            async let waitlist: [WaitlistEntry] = api.get("/waitlist/\(venue.id)?status=WAITING,OFFERED")
            (self.reservations, self.tables, self.waitlist) = try await (reservations, tables, waitlist)
            OperationWidgetSync.update(
                venue: venue,
                reservations: self.reservations,
                tables: self.tables,
                waitlist: self.waitlist
            )
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Bugünün verileri yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
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

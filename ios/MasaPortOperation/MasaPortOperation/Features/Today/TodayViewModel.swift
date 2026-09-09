import Foundation
import Combine

private struct WaitlistOfferResult: Decodable {
    let id: Int
    let status: String
}

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var reservations: [Reservation] = []
    @Published private(set) var tables: [VenueTable] = []
    @Published private(set) var waitlist: [WaitlistEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var offeringEntryID: Int?
    @Published private(set) var offerErrorMessage: String?

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
            guard !error.isCancellation else { return }
            errorMessage = "Bugünün verileri yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    /// Bekleme listesindeki misafire masa teklifi gönderir.
    func sendOffer(for entry: WaitlistEntry, venue: Venue) async -> Bool {
        offeringEntryID = entry.id
        offerErrorMessage = nil
        defer { offeringEntryID = nil }

        do {
            let _: WaitlistOfferResult = try await api.post("/waitlist/\(venue.id)/entry/\(entry.id)/offer")
            await load(venue: venue)
            return true
        } catch let error as APIError {
            offerErrorMessage = error.isConflict
                ? "Bu kayıt veya masa uygunluğu başka bir ekranda değişti. Liste yenilendi."
                : (error.detail ?? error.message)
            await load(venue: venue)
            return false
        } catch {
            offerErrorMessage = "Teklif gönderilemedi. Masa uygunluğunu kontrol edip yeniden deneyin."
            return false
        }
    }

    func markConverted(_ entry: WaitlistEntry, venue: Venue) async -> Bool {
        offeringEntryID = entry.id
        offerErrorMessage = nil
        defer { offeringEntryID = nil }
        struct StatusRequest: Encodable { let status: String }
        do {
            let _: WaitlistOfferResult = try await api.put("/waitlist/entry/\(entry.id)/status", body: StatusRequest(status: "CONVERTED"))
            await load(venue: venue)
            return true
        } catch let error as APIError {
            offerErrorMessage = "Walk-in oluşturuldu ancak bekleme kaydı kapatılamadı: \(error.detail ?? error.message)"
            await load(venue: venue)
            return false
        } catch {
            offerErrorMessage = "Walk-in oluşturuldu ancak bekleme kaydı kapatılamadı. Listeden elle kaldırın."
            return false
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

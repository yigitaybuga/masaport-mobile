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
    /// Son başarılı yüklemenin mekanı; hata bildirimi varken eski veri yalnızca aynı mekan içinse gösterilir.
    @Published private(set) var loadedVenueID: Int?

    private let api: APIClient
    private var loadGate = LoadGate()

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// `silent`: ekranda veri varken yapılan arka plan tazelemesi (ön plana dönüş, düzenli yenileme).
    func load(venue: Venue, silent: Bool = false) async {
        guard let generation = loadGate.begin(silent: silent) else { return }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        defer {
            if loadGate.isCurrent(generation) { isLoading = false }
            loadGate.end(generation)
        }

        let today = Self.todayString()
        do {
            async let reservations: [Reservation] = api.get("/reservations/\(venue.id)?date=\(today)&per_page=250&sort_by=startTime&sort_order=asc")
            async let tables: [VenueTable] = api.get("/tables/\(venue.id)")
            async let waitlist: [WaitlistEntry] = api.get("/waitlist/\(venue.id)?status=WAITING,OFFERED")
            let loaded = try await (reservations, tables, waitlist)
            // Bu arada daha yeni bir yükleme başladıysa eski yanıt onun üzerine yazılmaz.
            guard loadGate.isCurrent(generation) else { return }
            (self.reservations, self.tables, self.waitlist) = loaded
            loadedVenueID = venue.id
            errorMessage = nil
            // Her başarılı yenileme widget özetini yeniden yazar ve WidgetKit zaman çizelgesini tazeler.
            OperationWidgetSync.update(
                venue: venue,
                reservations: self.reservations,
                tables: self.tables,
                waitlist: self.waitlist
            )
        } catch let error as APIError {
            guard loadGate.isCurrent(generation) else { return }
            errorMessage = error.message
        } catch {
            guard loadGate.isCurrent(generation), !error.isCancellation else { return }
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
        do {
            let _: WaitlistOfferResult = try await api.put(
                "/waitlist/entry/\(entry.id)/status",
                body: WaitlistStatusUpdateRequest(status: "CONVERTED", venueID: venue.id)
            )
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

import Foundation

private struct WaitlistActionResponse: Decodable {
    let id: Int
    let status: String
}

@MainActor
final class WaitlistViewModel: ObservableObject {
    @Published private(set) var entries: [WaitlistEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var actionEntryID: Int?
    @Published private(set) var errorMessage: String?

    private let api: APIClient
    private var loadGate = LoadGate()

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// `silent`: ön plana dönüşteki arka plan tazelemesi; süren yüklemenin üstüne binmez, hata bildirimini baştan sıfırlamaz.
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
            let loaded: [WaitlistEntry] = try await api.get(
                "/waitlist/\(venueID)?status=WAITING,OFFERED"
            )
            guard loadGate.isCurrent(generation) else { return }
            entries = loaded.sorted(by: Self.sortEntries)
            errorMessage = nil
        } catch let error as APIError {
            guard loadGate.isCurrent(generation) else { return }
            errorMessage = error.message
        } catch {
            guard loadGate.isCurrent(generation), !error.isCancellation else { return }
            errorMessage = "Bekleme listesi yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    func sendOffer(for entry: WaitlistEntry, venueID: Int) async -> Bool {
        actionEntryID = entry.id
        errorMessage = nil
        defer { actionEntryID = nil }

        do {
            let _: WaitlistActionResponse = try await api.post(
                "/waitlist/\(venueID)/entry/\(entry.id)/offer"
            )
            await load(venueID: venueID)
            return true
        } catch let error as APIError {
            // Yeniden yükleme hata bildirimini sıfırlar; mesaj yüklemeden sonra yazılır.
            await load(venueID: venueID)
            errorMessage = error.isConflict
                ? "Bu kayıt veya masa uygunluğu başka bir ekranda değişti. Liste yenilendi."
                : error.message
            return false
        } catch {
            errorMessage = "Teklif gönderilemedi. Masa uygunluğunu kontrol edip yeniden deneyin."
            return false
        }
    }

    /// Walk-in kaydı oluşturulduktan sonra bekleme kaydını dönüştürüldü olarak kapatır.
    func markConverted(_ entry: WaitlistEntry, venueID: Int) async -> Bool {
        actionEntryID = entry.id
        errorMessage = nil
        defer { actionEntryID = nil }

        do {
            let _: WaitlistActionResponse = try await api.put(
                "/waitlist/entry/\(entry.id)/status",
                body: WaitlistStatusUpdateRequest(status: "CONVERTED", venueID: venueID)
            )
            await load(venueID: venueID)
            return true
        } catch let error as APIError {
            // Yeniden yükleme hata bildirimini sıfırlar; mesaj yüklemeden sonra yazılır.
            await load(venueID: venueID)
            errorMessage = "Walk-in oluşturuldu ancak bekleme kaydı kapatılamadı: \(error.detail ?? error.message)"
            return false
        } catch {
            errorMessage = "Walk-in oluşturuldu ancak bekleme kaydı kapatılamadı. Listeden elle kaldırın."
            return false
        }
    }

    func cancel(_ entry: WaitlistEntry, venueID: Int) async -> Bool {
        actionEntryID = entry.id
        errorMessage = nil
        defer { actionEntryID = nil }

        do {
            let _: WaitlistActionResponse = try await api.put(
                "/waitlist/entry/\(entry.id)/status",
                body: WaitlistStatusUpdateRequest(status: "CANCELLED", venueID: venueID)
            )
            await load(venueID: venueID)
            return true
        } catch let error as APIError {
            // Yeniden yükleme hata bildirimini sıfırlar; mesaj yüklemeden sonra yazılır.
            await load(venueID: venueID)
            errorMessage = error.isConflict
                ? "Kayıt başka bir ekranda değişti. Güncel liste yüklendi."
                : error.message
            return false
        } catch {
            errorMessage = "Bekleme kaydı iptal edilemedi. Tekrar deneyin."
            return false
        }
    }

    private static func sortEntries(_ lhs: WaitlistEntry, _ rhs: WaitlistEntry) -> Bool {
        if lhs.status != rhs.status {
            if lhs.status == "OFFERED" { return true }
            if rhs.status == "OFFERED" { return false }
        }
        if lhs.reservationDate != rhs.reservationDate {
            return lhs.reservationDate < rhs.reservationDate
        }
        let leftTime = lhs.timeSlot?.startTime ?? "99:99"
        let rightTime = rhs.timeSlot?.startTime ?? "99:99"
        if leftTime != rightTime { return leftTime < rightTime }
        return (lhs.createdAt ?? "") < (rhs.createdAt ?? "")
    }
}

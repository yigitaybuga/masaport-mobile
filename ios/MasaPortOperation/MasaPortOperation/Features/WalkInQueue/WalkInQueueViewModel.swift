import Foundation

/// Kapı sırası: masa doluyken gelen misafirleri sıraya ekleme, "masa hazır" bildirimi, oturtma ve sıradan çıkarma.
/// Web panelindeki "Kapı sırası" kartıyla aynı uçları kullanır (`/walk-in-queue/:venueId`).
@MainActor
final class WalkInQueueViewModel: ObservableObject {
    @Published private(set) var entries: [WalkInQueueEntry] = []
    @Published private(set) var minutesPerParty = 10
    @Published private(set) var suggestedQuoteMinutes = 15
    @Published private(set) var isLoading = false
    @Published private(set) var actionEntryID: Int?
    @Published private(set) var errorMessage: String?

    private let api: APIClient
    private var loadGate = LoadGate()

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// `silent`: ön plana dönüşteki ve dakikalık arka plan tazelemesi; hata bildirimini baştan sıfırlamaz.
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
            let snapshot: WalkInQueueSnapshot = try await api.get("/walk-in-queue/\(venueID)")
            guard loadGate.isCurrent(generation) else { return }
            apply(snapshot)
            errorMessage = nil
        } catch let error as APIError {
            guard loadGate.isCurrent(generation) else { return }
            errorMessage = error.detail ?? error.message
        } catch {
            guard loadGate.isCurrent(generation), !error.isCancellation else { return }
            errorMessage = "Kapı sırası yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }

    /// Başarılıysa misafire gösterilecek özet döner; hata `errorMessage` üzerinden okunur.
    func add(_ request: WalkInQueueCreateRequest, venueID: Int) async -> String? {
        errorMessage = nil
        do {
            let result: WalkInQueueCreateResult = try await api.post("/walk-in-queue/\(venueID)", body: request)
            await load(venueID: venueID)
            return WalkInQueueMessage.added(result)
        } catch let error as APIError {
            errorMessage = error.detail ?? error.message
            return nil
        } catch {
            errorMessage = "Misafir sıraya eklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
            return nil
        }
    }

    /// "Masa hazır": WhatsApp ve verildiyse e-postayla haber verir; tekrar basılırsa mesaj yeniden gönderilir.
    func notifyReady(_ entry: WalkInQueueEntry, venueID: Int) async -> String? {
        await perform(entry, venueID: venueID, fallback: "Bildirim gönderilemedi. Tekrar deneyin.") {
            let result: WalkInQueueNotifyResult = try await self.api.post(
                "/walk-in-queue/\(venueID)/\(entry.id)/notify",
                body: EmptyResponse()
            )
            return WalkInQueueMessage.ready(result, entry: entry)
        }
    }

    /// Masa açmadan sıradan düşürür (ör. telefonu olmayan misafir); bekleme süresi tahmin geçmişine katılır.
    func seatWithoutReservation(_ entry: WalkInQueueEntry, venueID: Int) async -> String? {
        await perform(entry, venueID: venueID, fallback: "Sıra kaydı güncellenemedi. Tekrar deneyin.") {
            let _: WalkInQueueEntry = try await self.api.post(
                "/walk-in-queue/\(venueID)/\(entry.id)/seat",
                body: EmptyResponse()
            )
            return "\(entry.customerName) oturtuldu olarak işaretlendi."
        }
    }

    /// `LEFT`: beklemeden ayrıldı, `CANCELLED`: sıradan çıkarıldı.
    func close(_ entry: WalkInQueueEntry, status: String, venueID: Int) async -> String? {
        await perform(entry, venueID: venueID, fallback: "Sıra kaydı güncellenemedi. Tekrar deneyin.") {
            let _: WalkInQueueEntry = try await self.api.post(
                "/walk-in-queue/\(venueID)/\(entry.id)/close",
                body: WalkInQueueCloseRequest(status: status)
            )
            return status == "LEFT" ? "\(entry.customerName) ayrıldı olarak işaretlendi." : "\(entry.customerName) sıradan çıkarıldı."
        }
    }

    private func perform(
        _ entry: WalkInQueueEntry,
        venueID: Int,
        fallback: String,
        operation: () async throws -> String
    ) async -> String? {
        actionEntryID = entry.id
        errorMessage = nil
        defer { actionEntryID = nil }

        do {
            let message = try await operation()
            await load(venueID: venueID)
            return message
        } catch let error as APIError {
            // Kayıt başka cihazda kapanmış olabilir; güncel liste yüklenir, mesaj yüklemeden sonra yazılır.
            await load(venueID: venueID)
            errorMessage = error.detail ?? error.message
            return nil
        } catch {
            errorMessage = fallback
            return nil
        }
    }

    private func apply(_ snapshot: WalkInQueueSnapshot) {
        entries = snapshot.active
            .filter(\.isActive)
            .sorted { ($0.position ?? .max, $0.id) < ($1.position ?? .max, $1.id) }
        if let minutes = snapshot.minutesPerParty, minutes > 0 { minutesPerParty = minutes }
        if let quote = snapshot.suggestedQuoteMinutes, quote > 0 { suggestedQuoteMinutes = quote }
    }
}

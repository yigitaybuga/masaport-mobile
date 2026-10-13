import Foundation
import Observation

/// Favoriler cihazda saklanır. Giriş yapılmışsa `AppModel` hesapla senkronlar:
/// - Hesabın bu cihazdaki ilk oturumunda girişten önce eklenenler hesaba katılır (yalnızca bir kez).
/// - Sonrasında hesap asıl kaynaktır; cihazdaki her değişiklik `pendingChanges` kuyruğuna yazılır
///   ve sırayla gönderilir. Gönderilemeyenler (çevrimdışı) sunucu listesinin üstüne uygulanır.
/// - Oturum kapanınca hesabın favorileri cihazdan silinir; bir sonraki hesaba karışmaz.
@MainActor
@Observable
final class FavoritesStore {
    struct Item: Codable, Hashable, Identifiable {
        enum Kind: String, Codable { case listing, event }

        let kind: Kind
        let remoteId: Int
        let title: String
        let subtitle: String?
        let image: String?
        let slug: String?
        let addedAt: Date

        var id: String { "\(kind.rawValue)-\(remoteId)" }
    }

    /// Hesaba henüz yazılmamış son durum; aynı kayıt için yalnızca en son değişiklik tutulur.
    struct PendingChange: Codable, Hashable {
        let item: Item
        let favorite: Bool
    }

    private struct SyncState: Codable {
        var accountId: Int?
        var pending: [PendingChange]
    }

    private(set) var items: [Item] = []
    private(set) var pendingChanges: [PendingChange] = []
    /// Cihazdaki listenin bağlı olduğu hesap; nil ise misafir (oturumsuz) favorileri.
    private(set) var syncedAccountId: Int?
    private let fileURL: URL
    private let syncStateURL: URL
    /// Kuyruğa yeni değişiklik girince çağrılır (oturum açıkken gönderimi başlatır).
    var onRemoteChange: (@MainActor () -> Void)?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appending(path: "favorites.json")
        syncStateURL = base.appending(path: "favorites-sync.json")
        load()
    }

    func isFavorite(listing id: Int) -> Bool { items.contains { $0.kind == .listing && $0.remoteId == id } }
    func isFavorite(event id: Int) -> Bool { items.contains { $0.kind == .event && $0.remoteId == id } }

    var listings: [Item] { items.filter { $0.kind == .listing } }
    var events: [Item] { items.filter { $0.kind == .event } }

    func toggle(_ item: Item) {
        let added: Bool
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            added = false
        } else {
            items.insert(item, at: 0)
            added = true
        }
        persist()
        recordChange(item, favorite: added)
    }

    func remove(id: String) {
        let removed = items.filter { $0.id == id }
        items.removeAll { $0.id == id }
        persist()
        removed.forEach { recordChange($0, favorite: false) }
    }

    /// Gönderilen değişiklik kuyruktan düşer; bu sırada yeniden değiştirildiyse yeni durum kalır.
    func completePendingChange(_ change: PendingChange) {
        pendingChanges.removeAll { $0 == change }
        persistSyncState()
    }

    func markSynced(accountId: Int) {
        syncedAccountId = accountId
        persistSyncState()
    }

    /// Oturum kapanınca veya hesap değişince hesabın favorileri cihazdan kaldırılır.
    func resetForSignedOut() {
        items = []
        pendingChanges = []
        syncedAccountId = nil
        persist()
        persistSyncState()
    }

    private func recordChange(_ item: Item, favorite: Bool) {
        // Oturumsuz favoriler yalnızca cihazdadır; ilk girişte topluca hesaba eklenir.
        guard syncedAccountId != nil else { return }
        pendingChanges.removeAll { $0.item.id == item.id }
        pendingChanges.append(PendingChange(item: item, favorite: favorite))
        persistSyncState()
        onRemoteChange?()
    }

    /// Hesaptaki liste cihazdakinin yerini alır; henüz gönderilemeyen değişiklikler üstüne uygulanır.
    func replace(with remote: [CustomerFavorite]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var merged: [Item] = remote.compactMap { favorite in
            guard let kind = Item.Kind(rawValue: favorite.kind) else { return nil }
            let local = items.first { $0.kind == kind && $0.remoteId == favorite.id }
            return Item(
                kind: kind,
                remoteId: favorite.id,
                title: favorite.title,
                subtitle: favorite.subtitle ?? local?.subtitle,
                image: favorite.image ?? local?.image,
                slug: favorite.slug ?? local?.slug,
                addedAt: favorite.addedAt.flatMap(formatter.date(from:)) ?? local?.addedAt ?? .now
            )
        }
        for change in pendingChanges {
            merged.removeAll { $0.id == change.item.id }
            if change.favorite { merged.insert(change.item, at: 0) }
        }
        items = merged
        persist()
    }

    private func load() {
        if let data = try? Data(contentsOf: syncStateURL),
           let state = try? JSONDecoder().decode(SyncState.self, from: data) {
            syncedAccountId = state.accountId
            pendingChanges = state.pending
        }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded
    }

    private func persistSyncState() {
        do {
            try FileManager.default.createDirectory(at: syncStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SyncState(accountId: syncedAccountId, pending: pendingChanges))
            try data.write(to: syncStateURL, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("Favori senkron durumu kaydedilemedi: \(error)")
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("Favoriler kaydedilemedi: \(error)")
        }
    }
}

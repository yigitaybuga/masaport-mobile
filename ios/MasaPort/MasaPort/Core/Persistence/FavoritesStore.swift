import Foundation
import Observation

/// Favoriler cihazda saklanır; sunucuda tüketici hesabı bulunmadığı için senkron edilmez.
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

    private(set) var items: [Item] = []
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appending(path: "favorites.json")
        load()
    }

    func isFavorite(listing id: Int) -> Bool { items.contains { $0.kind == .listing && $0.remoteId == id } }
    func isFavorite(event id: Int) -> Bool { items.contains { $0.kind == .event && $0.remoteId == id } }

    var listings: [Item] { items.filter { $0.kind == .listing } }
    var events: [Item] { items.filter { $0.kind == .event } }

    func toggle(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        } else {
            items.insert(item, at: 0)
        }
        persist()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded
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

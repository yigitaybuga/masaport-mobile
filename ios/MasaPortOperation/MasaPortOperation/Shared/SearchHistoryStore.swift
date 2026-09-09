import Foundation
import Combine

/// Arama alanı için cihazda tutulan son sorgular (kişisel veri sunucuya gitmez).
@MainActor
final class SearchHistoryStore: ObservableObject {
    @Published private(set) var queries: [String] = []

    private let key: String
    private let limit: Int
    private let defaults: UserDefaults

    init(scope: String, limit: Int = 8, defaults: UserDefaults = .standard) {
        self.key = "search-history.\(scope)"
        self.limit = limit
        self.defaults = defaults
        queries = defaults.stringArray(forKey: key) ?? []
    }

    func record(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        var next = queries.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        next.insert(query, at: 0)
        queries = Array(next.prefix(limit))
        defaults.set(queries, forKey: key)
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        defaults.set(queries, forKey: key)
    }

    func clear() {
        queries = []
        defaults.removeObject(forKey: key)
    }
}

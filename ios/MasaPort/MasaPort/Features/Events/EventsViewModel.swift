import Foundation
import Observation

@MainActor
@Observable
final class EventsViewModel {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    let preset: EventsPreset

    private(set) var phase: Phase = .idle
    private(set) var events: [PublicEvent] = []
    private(set) var categories: [EventCategory] = []
    private(set) var total = 0
    private(set) var hasMore = false
    private(set) var isLoadingMore = false

    var range: EventsDateRange
    var categoryId: Int?
    var cityId: Int?
    var searchText = ""

    private let api: PublicAPI
    private var page = 1
    private var activeTask: Task<Void, Never>?

    init(preset: EventsPreset, api: PublicAPI = .shared) {
        self.preset = preset
        self.api = api
        range = preset.range
        categoryId = preset.categoryId
    }

    private func makeQuery(page: Int) -> EventsQuery {
        var query = EventsQuery()
        query.page = page
        query.perPage = 24
        let bounds = range.bounds()
        query.startDate = bounds.start
        query.endDate = bounds.end
        query.cityId = cityId
        query.categoryId = categoryId
        query.search = searchText.nilIfBlank
        return query
    }

    func load() {
        activeTask?.cancel()
        phase = events.isEmpty ? .loading : .loaded
        page = 1
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await api.events(makeQuery(page: 1))
                guard !Task.isCancelled else { return }
                events = result.events
                total = result.pagination?.total ?? result.events.count
                hasMore = (result.pagination?.totalPages ?? 1) > 1
                phase = .loaded
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                if events.isEmpty {
                    phase = .failed((error as? APIError)?.message ?? error.localizedDescription)
                } else {
                    phase = .loaded
                }
            }
        }
    }

    func loadMoreIfNeeded(current: PublicEvent) async {
        guard hasMore, !isLoadingMore, let index = events.firstIndex(of: current), index >= events.count - 6 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = page + 1
            let result = try await api.events(makeQuery(page: next))
            let existing = Set(events.map(\.id))
            events.append(contentsOf: result.events.filter { !existing.contains($0.id) })
            page = next
            hasMore = next < (result.pagination?.totalPages ?? next)
        } catch {
            hasMore = false
        }
    }

    func loadCategories() async {
        guard categories.isEmpty else { return }
        categories = (try? await api.eventCategories()) ?? []
    }
}

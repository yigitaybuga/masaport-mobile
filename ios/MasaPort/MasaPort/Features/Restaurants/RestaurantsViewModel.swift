import Foundation
import Observation

@MainActor
@Observable
final class RestaurantsViewModel {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    let preset: ListingsPreset

    private(set) var phase: Phase = .idle
    private(set) var listings: [ListingCard] = []
    private(set) var total = 0
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var filters: ListingFilters?

    // Kullanıcı filtreleri
    var date: Date?
    var startTime: String?
    var guestCount: Int?
    var cityId: Int?
    var districtId: Int?
    var orderBy: String
    var searchText = ""

    private var coordinate: (Double, Double)?
    private let api: PublicAPI
    private let pageSize = 24
    private var activeTask: Task<Void, Never>?

    init(preset: ListingsPreset, api: PublicAPI = .shared) {
        self.preset = preset
        self.api = api
        date = preset.query.date.flatMap(DateFormat.parseAPIDay)
        startTime = preset.query.startTime
        guestCount = preset.query.guestCount
        cityId = preset.query.cityId
        districtId = preset.query.districtId
        orderBy = preset.query.orderBy ?? "rating"
        searchText = preset.query.query ?? ""
    }

    var hasAvailabilityFilter: Bool { date != nil || startTime != nil || guestCount != nil }
    var activeFilterCount: Int {
        [date != nil, startTime != nil, guestCount != nil, districtId != nil].filter { $0 }.count
    }

    var availabilitySummary: String? {
        guard hasAvailabilityFilter else { return nil }
        var parts: [String] = []
        if let date { parts.append(Format.relativeDay(date)) }
        if let startTime { parts.append(startTime.shortTime) }
        if let guestCount { parts.append(Format.guests(guestCount)) }
        return parts.joined(separator: " · ")
    }

    func setCoordinate(latitude: Double, longitude: Double) {
        coordinate = (latitude, longitude)
    }

    private func makeQuery(offset: Int) -> ListingsQuery {
        var query = preset.query
        query.limit = pageSize
        query.offset = offset
        query.orderBy = orderBy
        query.query = searchText.nilIfBlank
        query.cityId = cityId
        query.districtId = districtId
        query.date = date.map { DateFormat.apiDay.string(from: $0) }
        query.startTime = startTime
        query.guestCount = guestCount
        query.listingIds = preset.listingIds
        if preset.useLocation, let coordinate {
            query.latitude = coordinate.0
            query.longitude = coordinate.1
            query.radiusKm = 25
        }
        return query
    }

    func load(reset: Bool = true) {
        activeTask?.cancel()
        if reset {
            phase = listings.isEmpty ? .loading : .loaded
        }
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.listings(makeQuery(offset: 0))
                guard !Task.isCancelled else { return }
                listings = page.listings
                total = page.pagination?.total ?? page.listings.count
                hasMore = page.pagination?.hasMore ?? false
                phase = .loaded
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                if listings.isEmpty {
                    phase = .failed((error as? APIError)?.message ?? error.localizedDescription)
                } else {
                    phase = .loaded
                }
            }
        }
    }

    func loadMoreIfNeeded(current: ListingCard) async {
        guard hasMore, !isLoadingMore, let index = listings.firstIndex(of: current), index >= listings.count - 6 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.listings(makeQuery(offset: listings.count))
            let existing = Set(listings.map(\.id))
            listings.append(contentsOf: page.listings.filter { !existing.contains($0.id) })
            hasMore = page.pagination?.hasMore ?? false
        } catch {
            hasMore = false
        }
    }

    func loadFilters() async {
        filters = try? await api.listingFilters(cityId: cityId)
    }

    func clearAvailability() {
        date = nil
        startTime = nil
        guestCount = nil
        load()
    }
}

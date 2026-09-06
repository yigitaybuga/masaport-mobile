import Foundation
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var feed: DiscoveryFeed?
    private(set) var eventsFeed: DiscoveryFeed?
    private(set) var hydratedListings: [Int: ListingCard] = [:]
    private(set) var nearby: [ListingCard] = []
    /// Feed'de popüler modül boş geldiğinde gösterilen yedek liste.
    private(set) var topRated: [ListingCard] = []
    private(set) var loadedCityId: Int?

    // Hızlı rezervasyon paneli
    var quickDate: Date = Calendar.istanbul.startOfDay(for: .now)
    var quickGuests = 2

    private let api: PublicAPI

    init(api: PublicAPI = .shared) {
        self.api = api
    }

    var collections: [DiscoveryCard] {
        feed?.module("featured_collections")?.rotatedCards(seed: seed, limit: 6) ?? []
    }

    var cuisines: [DiscoveryCard] {
        feed?.module("cuisine_explorer")?.rotatedCards(seed: seed, limit: 8) ?? []
    }

    var popular: [DiscoveryCard] {
        feed?.module("popular_restaurants")?.rotatedCards(seed: seed, limit: 10) ?? []
    }

    var popularModule: DiscoveryModule? { feed?.module("popular_restaurants") }

    var showcaseEvents: [PublicEvent] {
        (eventsFeed?.module("events_showcase")?.rotatedCards(seed: seed, limit: 10) ?? []).map(\.asPublicEvent)
    }

    private var seed: Int {
        feed?.rotationBucket ?? Int(Date.now.timeIntervalSince1970 / (4 * 3600))
    }

    func load(cityId: Int?, force: Bool = false) async {
        if !force, phase == .loaded, loadedCityId == cityId { return }
        if feed == nil { phase = .loading }
        loadedCityId = cityId
        do {
            async let homepage = api.discoveryFeed(surface: "homepage", cityId: cityId)
            async let events = api.discoveryFeed(surface: "events", cityId: cityId)
            let (homeResult, eventsResult) = try await (homepage, events)
            feed = homeResult
            eventsFeed = eventsResult
            phase = .loaded
            if popular.isEmpty {
                await loadTopRated(cityId: cityId)
            } else {
                await hydratePopular()
            }
        } catch {
            if feed == nil {
                phase = .failed((error as? APIError)?.message ?? error.localizedDescription)
            } else {
                phase = .loaded
            }
        }
    }

    /// Feed CDN'de önbelleklendiği için müsaitlik ayrıca alınır (bugün, 2 kişi).
    private func hydratePopular() async {
        let ids = popular.map(\.id)
        guard !ids.isEmpty else { return }
        var query = ListingsQuery()
        query.limit = ids.count
        query.listingIds = ids
        query.date = DateFormat.apiDay.string(from: .now)
        query.guestCount = 2
        guard let page = try? await api.listings(query) else { return }
        var map: [Int: ListingCard] = [:]
        for listing in page.listings { map[listing.id] = listing }
        hydratedListings = map
    }

    private func loadTopRated(cityId: Int?) async {
        var query = ListingsQuery()
        query.limit = 10
        query.orderBy = "rating"
        query.cityId = cityId
        if let page = try? await api.listings(query) {
            topRated = page.listings
        }
    }

    func loadNearby(latitude: Double, longitude: Double) async {
        var query = ListingsQuery()
        query.limit = 12
        query.orderBy = "distance"
        query.latitude = latitude
        query.longitude = longitude
        query.radiusKm = 25
        query.date = DateFormat.apiDay.string(from: .now)
        query.guestCount = 2
        if let page = try? await api.listings(query) {
            nearby = page.listings
        }
    }

    var quickPreset: ListingsPreset {
        var query = ListingsQuery()
        query.date = DateFormat.apiDay.string(from: quickDate)
        query.guestCount = quickGuests
        query.cityId = loadedCityId
        return ListingsPreset(title: "Müsait masalar", query: query)
    }
}

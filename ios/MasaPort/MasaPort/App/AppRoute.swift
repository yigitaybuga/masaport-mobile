import SwiftUI

/// Sekmeler arasında paylaşılan gezinme hedefleri.
enum AppRoute: Hashable {
    case listing(slug: String)
    case eventByID(id: Int)
    case eventByIdentifier(identifier: String)
    case listings(ListingsPreset)
    case events(EventsPreset)
    case favorites
    case reservation(SavedReservation)
}

enum AppDeepLink: Hashable {
    case listing(slug: String)
    case event(identifier: String)

    var tab: AppTab {
        switch self {
        case .listing: .restaurants
        case .event: .events
        }
    }

    var route: AppRoute {
        switch self {
        case .listing(let slug): .listing(slug: slug)
        case .event(let identifier):
            if let id = Int(identifier) {
                .eventByID(id: id)
            } else {
                .eventByIdentifier(identifier: identifier)
            }
        }
    }

    /// Supports both the app's custom scheme and the canonical masaport.com paths.
    static func parse(_ url: URL) -> Self? {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let isAppScheme = scheme == "masaport"
        let isWebLink = (scheme == "http" || scheme == "https") &&
            (host == "masaport.com" || host == "www.masaport.com")
        guard isAppScheme || isWebLink else { return nil }

        var segments: [String] = []
        if isAppScheme, let host {
            segments.append(host)
        }
        segments += url.path.split(separator: "/").map(String.init)

        guard let first = segments.first else { return nil }
        if (first == "restaurant" || first == "listing"), let slug = segments.dropFirst().first, !slug.isEmpty {
            return .listing(slug: slug)
        }
        if first == "event", let identifier = segments.dropFirst().first, !identifier.isEmpty {
            return .event(identifier: identifier)
        }
        if segments.count >= 3, segments[1] == "restoranlar", !segments[2].isEmpty {
            return .listing(slug: segments[2])
        }
        if segments.count >= 3, segments[1] == "etkinlikler", !segments[2].isEmpty {
            return .event(identifier: segments[2])
        }
        if first == "etkinlikler", let identifier = segments.dropFirst().first, !identifier.isEmpty {
            return .event(identifier: identifier)
        }
        return nil
    }
}

struct ListingsPreset: Hashable {
    var title: String = "Restoranlar"
    var query: ListingsQuery = ListingsQuery()
    var listingIds: [Int] = []
    var useLocation = false

    /// Discovery kartından (koleksiyon veya mutfak) liste ön ayarı üretir.
    init(card: DiscoveryCard) {
        title = card.displayTitle
        listingIds = card.resolvedListingIds
        if listingIds.isEmpty, let cuisine = card.resolvedCuisine {
            query.cuisine = [cuisine]
        } else if listingIds.isEmpty, let term = card.hrefQueryItems.first(where: { $0.name == "query" })?.value?.nilIfBlank {
            query.query = term
        }
    }

    init(title: String = "Restoranlar", query: ListingsQuery = ListingsQuery(), listingIds: [Int] = [], useLocation: Bool = false) {
        self.title = title
        self.query = query
        self.listingIds = listingIds
        self.useLocation = useLocation
    }
}

struct EventsPreset: Hashable {
    var title: String = "Etkinlikler"
    var categoryId: Int? = nil
    var range: EventsDateRange = .all
}

enum EventsDateRange: String, CaseIterable, Hashable, Identifiable {
    case all, today, weekend, week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .today: "Bugün"
        case .weekend: "Hafta sonu"
        case .week: "Bu hafta"
        }
    }

    /// API'nin beklediği `start_date`/`end_date` çifti.
    func bounds(now: Date = .now, calendar: Calendar = .istanbul) -> (start: String, end: String?) {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .all:
            return (DateFormat.apiDay.string(from: today), nil)
        case .today:
            return (DateFormat.apiDay.string(from: today), DateFormat.apiDay.string(from: today))
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: today) ?? today
            return (DateFormat.apiDay.string(from: today), DateFormat.apiDay.string(from: end))
        case .weekend:
            let weekday = calendar.component(.weekday, from: today) // 1 Pazar ... 7 Cumartesi
            let daysToSaturday = (7 - weekday + 7) % 7
            let saturday = weekday == 1 ? today : (calendar.date(byAdding: .day, value: daysToSaturday, to: today) ?? today)
            let start = weekday == 1 ? today : saturday
            let end = weekday == 1 ? today : (calendar.date(byAdding: .day, value: 1, to: saturday) ?? saturday)
            return (DateFormat.apiDay.string(from: start), DateFormat.apiDay.string(from: end))
        }
    }
}

extension View {
    /// Her sekmenin NavigationStack'ine ortak hedefleri bağlar.
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .listing(let slug):
                RestaurantDetailView(slug: slug)
            case .eventByID(id: let id):
                EventDetailView(eventID: id)
            case .eventByIdentifier(identifier: let identifier):
                EventDetailView(identifier: identifier)
            case .listings(let preset):
                RestaurantsView(preset: preset)
            case .events(let preset):
                EventsView(preset: preset)
            case .favorites:
                FavoritesView()
            case .reservation(let reservation):
                ReservationTicketView(reservation: reservation)
            }
        }
    }
}

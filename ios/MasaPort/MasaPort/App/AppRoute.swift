import SwiftUI

/// Sekmeler arasında paylaşılan gezinme hedefleri.
enum AppRoute: Hashable {
    case listing(slug: String)
    case event(id: Int)
    case listings(ListingsPreset)
    case events(EventsPreset)
    case favorites
    case reservation(SavedReservation)
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
            case .event(let id):
                EventDetailView(eventID: id)
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

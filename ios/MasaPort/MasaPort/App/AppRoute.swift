import SwiftUI

/// Sekmeler arasında paylaşılan gezinme hedefleri.
enum AppRoute: Hashable {
    /// `prefill` yalnızca kısa rezervasyon bağlantısından gelir; detay açılınca rezervasyon akışı başlar.
    case listing(slug: String, prefill: BookingPrefill? = nil)
    case eventByID(id: Int)
    case eventByIdentifier(identifier: String)
    case listings(ListingsPreset)
    case events(EventsPreset)
    case favorites
    case reservation(SavedReservation)
}

enum AppDeepLink: Hashable {
    case listing(slug: String, prefill: BookingPrefill? = nil)
    case event(identifier: String)

    var tab: AppTab {
        switch self {
        case .listing: .restaurants
        case .event: .events
        }
    }

    var route: AppRoute {
        switch self {
        case .listing(let slug, let prefill): .listing(slug: slug, prefill: prefill)
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

        // Boş veya yalnızca boşluktan oluşan parçalar (`/istanbul/restoranlar/`, `/etkinlikler/%20`) rota üretmez.
        func identifier(at index: Int) -> String? {
            guard segments.indices.contains(index) else { return nil }
            let value = segments[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value == "." || value == ".." ? nil : value
        }

        guard let first = segments.first else { return nil }
        // Kısa rezervasyon bağlantısı: slug, restoranın listing slug'ıdır (eski slug'lar sunucuda yönlendirilir).
        if first == "r", let slug = identifier(at: 1) {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return .listing(slug: slug, prefill: BookingPrefill(queryItems: items))
        }
        if first == "restaurant" || first == "listing" {
            return identifier(at: 1).map { .listing(slug: $0) }
        }
        if first == "event" {
            return identifier(at: 1).map { .event(identifier: $0) }
        }
        if segments.count >= 2, segments[1] == "restoranlar" {
            return identifier(at: 2).map { .listing(slug: $0) }
        }
        if segments.count >= 2, segments[1] == "etkinlikler" {
            return identifier(at: 2).map { .event(identifier: $0) }
        }
        if first == "etkinlikler" {
            return identifier(at: 1).map { .event(identifier: $0) }
        }
        return nil
    }
}

/// Kısa rezervasyon bağlantısındaki (`/r/{slug}?date=&time=&guests=`) ön seçim.
/// Geçersiz veya seçilebilir aralık dışındaki değerler sessizce yok sayılır.
struct BookingPrefill: Hashable {
    /// Gün şeridiyle aynı: bugünden itibaren 14 gün seçilebilir.
    static let bookableDays = 14
    static let guestRange = 1...12

    var date: Date?
    var time: String?
    var guests: Int?

    init(date: Date? = nil, time: String? = nil, guests: Int? = nil) {
        self.date = date
        self.time = time
        self.guests = guests
    }

    init(queryItems: [URLQueryItem], now: Date = .now, calendar: Calendar = .istanbul) {
        func value(_ name: String) -> String? {
            queryItems.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        if let raw = value("date"), raw.wholeMatch(of: #/\d{4}-\d{2}-\d{2}/#) != nil,
           let day = DateFormat.parseAPIDay(raw), DateFormat.apiDay.string(from: day) == raw {
            let today = calendar.startOfDay(for: now)
            let last = calendar.date(byAdding: .day, value: Self.bookableDays - 1, to: today) ?? today
            if day >= today, day <= last { date = day }
        }
        if let raw = value("time"), raw.wholeMatch(of: #/([01]\d|2[0-3]):[0-5]\d/#) != nil {
            time = raw
        }
        if let raw = value("guests"), let count = Int(raw), Self.guestRange.contains(count) {
            guests = count
        }
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
            case .listing(let slug, let prefill):
                RestaurantDetailView(slug: slug, prefill: prefill)
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

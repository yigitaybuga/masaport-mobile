import SwiftUI

enum AppTab: Hashable {
    case discover, restaurants, events, reservations, search
}

struct AppRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .discover
    @State private var discoverPath: [AppRoute] = []
    @State private var restaurantsPath: [AppRoute] = []
    @State private var eventsPath: [AppRoute] = []
    @State private var reservationsPath: [AppRoute] = []
    @State private var searchPath: [AppRoute] = []

    var body: some View {
        TabView(selection: $selection) {
            Tab("Keşfet", systemImage: "sparkles", value: .discover) {
                NavigationStack(path: $discoverPath) { DiscoverView().appRoutes() }
            }
            Tab("Restoranlar", systemImage: "fork.knife", value: .restaurants) {
                NavigationStack(path: $restaurantsPath) { RestaurantsView(preset: ListingsPreset()).appRoutes() }
            }
            Tab("Etkinlikler", systemImage: "ticket", value: .events) {
                NavigationStack(path: $eventsPath) { EventsView(preset: EventsPreset()).appRoutes() }
            }
            Tab("Rezervasyonlar", systemImage: "calendar", value: .reservations) {
                NavigationStack(path: $reservationsPath) { MyReservationsView().appRoutes() }
            }
            Tab(value: .search, role: .search) {
                NavigationStack(path: $searchPath) { SearchView().appRoutes() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL(perform: handleDeepLink)
    }

    private func handleDeepLink(_ url: URL) {
        guard let deepLink = AppDeepLink.parse(url) else { return }
        selection = deepLink.tab

        switch deepLink.tab {
        case .discover:
            discoverPath = [deepLink.route]
        case .restaurants:
            restaurantsPath = [deepLink.route]
        case .events:
            eventsPath = [deepLink.route]
        case .reservations:
            reservationsPath = [deepLink.route]
        case .search:
            searchPath = [deepLink.route]
        }
    }
}

import SwiftUI

enum AppTab: Hashable {
    case discover, restaurants, events, reservations, search
}

struct AppRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .discover

    var body: some View {
        TabView(selection: $selection) {
            Tab("Keşfet", systemImage: "sparkles", value: .discover) {
                NavigationStack { DiscoverView().appRoutes() }
            }
            Tab("Restoranlar", systemImage: "fork.knife", value: .restaurants) {
                NavigationStack { RestaurantsView(preset: ListingsPreset()).appRoutes() }
            }
            Tab("Etkinlikler", systemImage: "ticket", value: .events) {
                NavigationStack { EventsView(preset: EventsPreset()).appRoutes() }
            }
            Tab("Rezervasyonlar", systemImage: "calendar", value: .reservations) {
                NavigationStack { MyReservationsView().appRoutes() }
            }
            Tab(value: .search, role: .search) {
                NavigationStack { SearchView().appRoutes() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

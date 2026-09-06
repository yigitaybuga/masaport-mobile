import Foundation
import Observation

/// Uygulama genelinde paylaşılan durum: konum, şehir, favoriler, yerel rezervasyonlar.
@MainActor
@Observable
final class AppModel {
    let api: PublicAPI
    let preferences: PreferencesStore
    let favorites: FavoritesStore
    let reservations: MyReservationsStore
    let location: LocationService
    let customerSession: CustomerSessionStore

    private(set) var locations: DiscoveryLocations?
    private(set) var paymentConfig: PaymentConfig?
    private(set) var resolvedCityFromLocation: CityRef?

    init(api: PublicAPI = .shared) {
        self.api = api
        preferences = PreferencesStore()
        favorites = FavoritesStore()
        reservations = MyReservationsStore()
        location = LocationService()
        customerSession = CustomerSessionStore(api: api)
    }

    init(api: PublicAPI, preferences: PreferencesStore, favorites: FavoritesStore, reservations: MyReservationsStore, location: LocationService) {
        self.api = api
        self.preferences = preferences
        self.favorites = favorites
        self.reservations = reservations
        self.location = location
        customerSession = CustomerSessionStore(api: api)
    }

    /// Kullanıcının açıkça seçtiği şehir; yoksa konumdan çözülen şehir.
    var activeCity: CityRef? { preferences.selectedCity ?? resolvedCityFromLocation }

    func bootstrap() async {
        async let locationsTask: Void = loadLocations()
        async let paymentTask: Void = loadPaymentConfig()
        async let sessionTask: Void = customerSession.restore()
        _ = await (locationsTask, paymentTask, sessionTask)
    }

    func loadLocations() async {
        guard locations == nil else { return }
        locations = try? await api.discoveryLocations()
    }

    func loadPaymentConfig() async {
        paymentConfig = await api.paymentConfig()
    }

    /// Konum izni alır ve şehir bilgisini çözer. Kullanıcı bir şehir seçmişse onu ezmez.
    func resolveCityFromLocation() async {
        await location.locate()
        guard let coordinate = location.coordinate else { return }
        if let resolution = try? await api.reverseGeocode(latitude: coordinate.latitude, longitude: coordinate.longitude),
           let city = resolution.city {
            resolvedCityFromLocation = city
        }
    }

    func selectCity(_ city: CityRef?) {
        preferences.selectedCity = city
    }

    /// Ön ödeme akışı uygulama içinde tamamlanabilir mi? Kart bilgisi isteyen sağlayıcılarda web'e devredilir.
    var canPayInApp: Bool { paymentConfig?.supportsHostedCheckout == true }
}

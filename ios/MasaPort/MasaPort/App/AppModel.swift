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
    /// Rezervasyon web'de iptal edildiğinde veya değiştirildiğinde artar; Rezervasyonlar listesi yeniden yüklenir.
    private(set) var reservationsRevision = 0

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

    /// Hesap değişince (açılışta da) çağrılır. Hesabın bu cihazdaki ilk oturumunda girişten önce
    /// eklenen favoriler hesaba katılır; sonrasında hesap asıl kaynaktır ve web'de silinen favori
    /// geri gelmez. Oturum kapanınca veya hesap değişince cihazdaki liste temizlenir.
    func syncFavoritesWithAccount() async {
        guard let account = customerSession.account else {
            favorites.onRemoteChange = nil
            if favorites.syncedAccountId != nil { favorites.resetForSignedOut() }
            return
        }
        if let synced = favorites.syncedAccountId, synced != account.id { favorites.resetForSignedOut() }
        favorites.onRemoteChange = { [weak self] in self?.flushFavoriteChanges() }
        do {
            let remote: [CustomerFavorite]
            if favorites.syncedAccountId == nil {
                remote = try await mergeDeviceFavorites()
                favorites.markSynced(accountId: account.id)
            } else {
                await flushFavoriteChanges().value
                remote = try await api.favorites()
            }
            guard customerSession.account?.id == account.id else { return }
            favorites.replace(with: remote)
        } catch {
            // Çevrimdışı: cihazdaki liste ve bekleyen değişiklikler korunur; sonraki açılışta denenir.
        }
    }

    /// Girişten önce cihazda eklenen favoriler hesaba eklenir (silme yapılmaz). Uç nokta istek
    /// başına en fazla 200 kayıt aldığı için parça parça gönderilir; son yanıt birleşik listedir.
    private func mergeDeviceFavorites() async throws -> [CustomerFavorite] {
        let all = favorites.listings.map { (FavoritesStore.Item.Kind.listing, $0.remoteId) }
            + favorites.events.map { (FavoritesStore.Item.Kind.event, $0.remoteId) }
        guard !all.isEmpty else { return try await api.favorites() }
        var remote: [CustomerFavorite] = []
        var start = 0
        while start < all.count {
            let chunk = all[start..<min(start + 200, all.count)]
            remote = try await api.syncFavorites(
                listingIds: chunk.filter { $0.0 == .listing }.map(\.1),
                eventIds: chunk.filter { $0.0 == .event }.map(\.1)
            )
            start += 200
        }
        return remote
    }

    private var favoriteFlushTask: Task<Void, Never>?
    private var favoritesNeedFlush = false

    /// Bekleyen favori değişikliklerini sırayla gönderir; aynı anda tek gönderim çalışır, böylece
    /// hızlı ekle/çıkar sırası sunucuda karışmaz.
    @discardableResult
    private func flushFavoriteChanges() -> Task<Void, Never> {
        if let running = favoriteFlushTask {
            favoritesNeedFlush = true
            return running
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.favoritesNeedFlush = false
                for change in self.favorites.pendingChanges {
                    do {
                        try await self.api.setFavorite(kind: change.item.kind, id: change.item.remoteId, favorite: change.favorite)
                        self.favorites.completePendingChange(change)
                    } catch let error as APIError where (400..<500).contains(error.statusCode) && error.statusCode != 401 && error.statusCode != 429 {
                        // Kalıcı ret (ör. yayından kalkmış restoran, limit): kuyruğu tıkamasın.
                        self.favorites.completePendingChange(change)
                    } catch {
                        // Ağ hatası: kuyruk korunur, sonraki değişiklikte veya açılışta yeniden denenir.
                        self.favoritesNeedFlush = false
                        break
                    }
                }
            } while self.favoritesNeedFlush
            self.favoriteFlushTask = nil
        }
        favoriteFlushTask = task
        return task
    }

    func reservationsDidChange() {
        reservationsRevision += 1
    }

    /// Ön ödeme akışı uygulama içinde tamamlanabilir mi? Kart bilgisi isteyen sağlayıcılarda web'e devredilir.
    var canPayInApp: Bool { paymentConfig?.supportsHostedCheckout == true }
}

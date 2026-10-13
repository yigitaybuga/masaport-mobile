import Foundation
import UIKit
import Combine

enum SessionState: Equatable {
    case launching
    case signedOut
    case signedIn
}

/// Oturum token'larının kalıcı deposu; testlerde Keychain yerine bellek içi sürüm kullanılır.
protocol SessionCredentialStore {
    func refreshToken() throws -> String?
    func installationID() throws -> String
    func save(accessToken: String, refreshToken: String) throws
    func deleteSession()
}

struct KeychainSessionCredentialStore: SessionCredentialStore {
    func refreshToken() throws -> String? { try KeychainStore.refreshToken() }
    func installationID() throws -> String { try KeychainStore.installationID() }

    func save(accessToken: String, refreshToken: String) throws {
        try KeychainStore.saveAccessToken(accessToken)
        try KeychainStore.saveRefreshToken(refreshToken)
    }

    func deleteSession() { KeychainStore.deleteSession() }
}

@MainActor
final class SessionStore: ObservableObject {
    static let expiredSessionMessage = "Oturumunun süresi doldu, lütfen tekrar giriş yap."

    @Published private(set) var state: SessionState = .launching
    @Published private(set) var user: OperationUser?
    @Published private(set) var venues: [Venue] = []
    @Published private(set) var activeVenue: Venue?
    @Published private(set) var accessToken: String?
    /// Oturum sunucu tarafından sonlandırıldığında giriş ekranında gösterilen kısa açıklama.
    @Published private(set) var signOutNotice: String?
    /// Açılışta oturum geçici bir hata yüzünden doğrulanamadıysa açılış ekranında gösterilir.
    @Published private(set) var launchIssue: String?
    @Published private(set) var isRestoring = false

    private let api: APIClient
    private let credentials: SessionCredentialStore
    private let clearSharedSnapshot: () -> Void
    private let activeVenueDefaultsKey = "active-operation-venue-id"
    private var refreshTask: Task<Void, Never>?
    private var restoreRetryTask: Task<Void, Never>?
    private var restoreAttempts = 0
    /// Sunucu refresh token'ı her yenilemede döndürür; Keychain yazımı başarısız olsa bile yenisi kaybolmasın.
    private var cachedRefreshToken: String?
    private var accessTokenExpiresAt: Date?

    init(
        api: APIClient = .shared,
        credentials: SessionCredentialStore = KeychainSessionCredentialStore(),
        clearSharedSnapshot: @escaping () -> Void = OperationWidgetSync.clear
    ) {
        self.api = api
        self.credentials = credentials
        self.clearSharedSnapshot = clearSharedSnapshot
        // Tüm yenilemeler (zamanlanmış, 401 sonrası, WebSocket) APIClient'ın tek uçuşlu yolundan geçer;
        // döndürülen refresh token aynı anda iki kez kullanılıp oturum yanlışlıkla düşürülmez.
        api.setRefreshHandler { [weak self] in
            await self?.performTokenRefresh() ?? .rejected
        }
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        let storedToken: String?
        do {
            storedToken = try credentials.refreshToken()
        } catch {
            // Cihaz kilitliyken Keychain okunamaz; bu, oturumun geçersiz olduğu anlamına gelmez.
            deferRestore()
            return
        }
        guard storedToken != nil else {
            state = .signedOut
            return
        }

        switch await api.refreshAccessToken() {
        case .refreshed:
            restoreAttempts = 0
            launchIssue = nil
            state = .signedIn
        case .rejected:
            // performTokenRefresh yerel oturumu temizledi ve giriş ekranına döndü.
            break
        case .unavailable:
            deferRestore()
        }
    }

    /// Açılış ekranındaki "Tekrar dene" ve ön plana dönüş, bekleyen otomatik denemeyi öne çeker.
    func retryRestore() async {
        guard state == .launching, launchIssue != nil, !isRestoring else { return }
        restoreRetryTask?.cancel()
        restoreRetryTask = nil
        await restore()
    }

    func login(email: String, password: String) async throws {
        let installationID = try credentials.installationID()
        let payload: MobileAuthPayload = try await api.post(
            "/mobile/auth/login",
            body: MobileLoginRequest(
                email: email,
                password: password,
                installationID: installationID,
                deviceName: UIDevice.current.name,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            )
        )
        guard payload.user.venueRoles.contains(where: { $0.role.canUseOperationsApp }) else {
            throw APIError(statusCode: 403, message: "Bu hesap Operasyon uygulaması için yetkili değil.", code: "MOBILE_ROLE_FORBIDDEN", requestId: nil)
        }
        do {
            try persist(payload)
        } catch {
            clearLocalSession()
            throw error
        }
        apply(user: payload.user, venues: payload.venues)
        signOutNotice = nil
        state = .signedIn
        scheduleRefresh(after: payload.expiresIn)
    }

    func selectVenue(_ venue: Venue) {
        guard venues.contains(venue) else { return }
        activeVenue = venue
        UserDefaults.standard.set(venue.id, forKey: activeVenueDefaultsKey)
    }

    func logout() async {
        if let refreshToken = try? cachedRefreshToken ?? credentials.refreshToken() {
            let _: EmptyResponse? = try? await api.post(
                "/mobile/auth/logout",
                body: MobileRefreshRequest(refreshToken: refreshToken)
            )
        }
        clearLocalSession()
    }

    /// Uygulama ön plana döndüğünde çağrılır: arka planda süresi dolmuş olabilecek erişim token'ını
    /// hemen yeniler, aksi halde zamanlayıcıyı kalan süreye göre yeniden kurar.
    func sceneDidBecomeActive() {
        switch state {
        case .launching:
            Task { await retryRestore() }
        case .signedIn:
            guard let expiresAt = accessTokenExpiresAt else { return }
            let remaining = expiresAt.timeIntervalSinceNow
            if remaining <= 60 {
                refreshTask?.cancel()
                refreshTask = Task { [api] in
                    _ = await api.refreshAccessToken()
                }
            } else {
                scheduleRefresh(after: Int(remaining))
            }
        case .signedOut:
            break
        }
    }

    private func persist(_ payload: MobileAuthPayload) throws {
        // Önce bellekteki durum: sunucu eski refresh token'ı artık kabul etmez.
        cachedRefreshToken = payload.refreshToken
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        api.setAccessToken(payload.accessToken)
        accessToken = payload.accessToken
        try credentials.save(accessToken: payload.accessToken, refreshToken: payload.refreshToken)
    }

    private func scheduleRefresh(after expiresIn: Int) {
        refreshTask?.cancel()
        let delay = Duration.seconds(max(60, expiresIn - 60))
        refreshTask = Task { [api] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            _ = await api.refreshAccessToken()
        }
    }

    /// Tek gerçek yenileme isteği. Yalnızca APIClient'ın tek uçuşlu yolu üzerinden çağrılır.
    private func performTokenRefresh() async -> TokenRefreshOutcome {
        guard state != .signedOut else { return .rejected }

        let refreshToken: String
        do {
            guard let stored = try cachedRefreshToken ?? credentials.refreshToken() else {
                clearLocalSession(notice: Self.expiredSessionMessage)
                return .rejected
            }
            refreshToken = stored
        } catch {
            if state == .signedIn { scheduleRefresh(after: 60) }
            return .unavailable
        }

        do {
            let payload: MobileAuthPayload = try await api.post(
                "/mobile/auth/refresh",
                body: MobileRefreshRequest(refreshToken: refreshToken)
            )
            // İstek sürerken kullanıcı çıkış yaptıysa yeni token'lar saklanmaz.
            guard state != .signedOut else { return .rejected }
            // Keychain yazılamasa bile yeni token'lar bellekte kalır; bir sonraki yenilemede tekrar yazılır.
            try? persist(payload)
            apply(user: payload.user, venues: payload.venues)
            scheduleRefresh(after: payload.expiresIn)
            return .refreshed(accessToken: payload.accessToken)
        } catch let error as APIError where error.rejectsSession {
            guard state != .signedOut else { return .rejected }
            clearLocalSession(notice: Self.expiredSessionMessage)
            return .rejected
        } catch {
            // An interrupted network does not discard a still-valid local session.
            if state == .signedIn { scheduleRefresh(after: 60) }
            return .unavailable
        }
    }

    private func deferRestore() {
        launchIssue = "Sunucuya ulaşılamadı. Bağlantı gelince oturumun otomatik açılacak."
        restoreAttempts += 1
        let delay = min(30, 2 << min(restoreAttempts, 4))
        restoreRetryTask?.cancel()
        restoreRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.restore()
        }
    }

    private func apply(user: OperationUser, venues: [Venue]) {
        let usableVenueIDs = Set(user.venueRoles.filter { $0.role.canUseOperationsApp }.map(\.venueId))
        self.user = user
        self.venues = venues.filter { usableVenueIDs.contains($0.id) }
        let savedVenueID = UserDefaults.standard.integer(forKey: activeVenueDefaultsKey)
        activeVenue = self.venues.first(where: { $0.id == savedVenueID }) ?? self.venues.first
    }

    private func clearLocalSession(notice: String? = nil) {
        refreshTask?.cancel()
        refreshTask = nil
        restoreRetryTask?.cancel()
        restoreRetryTask = nil
        restoreAttempts = 0
        launchIssue = nil
        credentials.deleteSession()
        cachedRefreshToken = nil
        accessTokenExpiresAt = nil
        api.setAccessToken(nil)
        accessToken = nil
        user = nil
        venues = []
        activeVenue = nil
        clearSharedSnapshot()
        signOutNotice = notice
        state = .signedOut
    }
}

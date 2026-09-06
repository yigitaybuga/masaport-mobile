import Foundation
import Observation

/// Tüketici hesabı oturumu. Refresh token Keychain'de, hesap özeti UserDefaults'ta,
/// erişim token'ı yalnızca bellekte tutulur ve gerektiğinde `/customer/auth/refresh` ile yenilenir.
@MainActor
@Observable
final class CustomerSessionStore: AccessTokenProviding {
    private enum Key {
        static let account = "masaport.customer.account"
    }

    private(set) var account: CustomerAccount?
    private(set) var isRestoring = true

    private var accessToken: String?
    private var accessExpiresAt: Date = .distantPast
    private var refreshTask: Task<String?, Never>?

    private let api: PublicAPI
    private let defaults: UserDefaults

    var isLoggedIn: Bool { account != nil }

    init(api: PublicAPI = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.account),
           let stored = try? JSONDecoder().decode(CustomerAccount.self, from: data),
           (try? KeychainStore.refreshToken()) != nil {
            account = stored
        }
        api.client.tokenProvider = self
    }

    /// Açılışta: refresh token varsa erişim token'ını sessizce yeniler ve hesabı tazeler.
    func restore() async {
        defer { isRestoring = false }
        guard account != nil else { return }
        if await refreshAccessToken() != nil {
            if let fresh = try? await api.customerAccount() {
                apply(account: fresh)
            }
        }
    }

    // MARK: AccessTokenProviding

    private var validCachedToken: String? {
        guard let accessToken, accessExpiresAt > .now.addingTimeInterval(20) else { return nil }
        return accessToken
    }

    nonisolated func currentAccessToken() async -> String? {
        if let token = await MainActor.run(body: { self.validCachedToken }) { return token }
        guard await MainActor.run(body: { self.account != nil }) else { return nil }
        return await refreshAccessToken()
    }

    nonisolated func refreshAccessToken() async -> String? {
        let task = await MainActor.run(body: { self.performRefresh() })
        return await task.value
    }

    private func performRefresh() -> Task<String?, Never> {
        if let refreshTask { return refreshTask }
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            defer { self.refreshTask = nil }
            guard let refreshToken = try? KeychainStore.refreshToken() else {
                self.clearLocalSession()
                return nil
            }
            do {
                let response = try await self.api.refreshCustomerSession(refreshToken: refreshToken)
                self.apply(session: response)
                return response.accessToken
            } catch let error as APIError where error.statusCode == 401 || error.statusCode == 400 {
                self.clearLocalSession()
                return nil
            } catch {
                // Ağ hatası: oturumu düşürme, mevcut token ile devam edilsin.
                return self.accessToken
            }
        }
        refreshTask = task
        return task
    }

    // MARK: Akışlar

    func register(name: String, email: String, phone: String?, password: String, marketingConsent: Bool) async throws -> CustomerRegisterPending {
        try await api.registerCustomer(.init(name: name, email: email, phone: phone, password: password, marketingConsent: marketingConsent))
    }

    func resendVerification(email: String) async throws -> CustomerRegisterPending {
        try await api.resendCustomerVerification(email: email)
    }

    func verify(email: String, code: String) async throws {
        let response = try await api.verifyCustomerRegistration(.init(email: email, code: code, installationId: KeychainStore.installationID()))
        apply(session: response)
    }

    func login(email: String, password: String) async throws {
        let response = try await api.loginCustomer(.init(email: email, password: password, installationId: KeychainStore.installationID()))
        apply(session: response)
    }

    func logout() async {
        let refreshToken = try? KeychainStore.refreshToken()
        clearLocalSession()
        if let refreshToken {
            try? await api.logoutCustomer(refreshToken: refreshToken)
        }
    }

    func forgotPassword(email: String) async throws -> String {
        try await api.requestCustomerPasswordReset(email: email)
    }

    func updateProfile(_ request: UpdateAccountRequest) async throws {
        let updated = try await api.updateCustomerAccount(request)
        apply(account: updated)
    }

    func updateProfile(name: String?, phone: String?, marketingConsent: Bool?) async throws {
        try await updateProfile(.init(name: name, phone: phone, marketingConsent: marketingConsent))
    }

    /// Şifre onayıyla hesabı kalıcı olarak siler; başarılıysa yerel oturum temizlenir.
    func deleteAccount(password: String) async throws {
        try await api.deleteCustomerAccount(password: password)
        clearLocalSession()
    }

    func deviceSessions() async throws -> [CustomerDeviceSession] {
        try await api.customerSessions()
    }

    /// Tek cihazı kapatır; bu cihazsa yerel oturum da düşer.
    func revokeDeviceSession(_ session: CustomerDeviceSession) async throws {
        try await api.revokeCustomerSession(id: session.id)
        if session.isCurrent { clearLocalSession() }
    }

    func revokeOtherDeviceSessions() async throws {
        try await api.revokeOtherCustomerSessions()
    }

    func changePassword(current: String, new: String) async throws {
        try await api.changeCustomerPassword(.init(currentPassword: current, newPassword: new))
    }

    func reservations() async throws -> [CustomerReservation] {
        try await api.customerReservations()
    }

    // MARK: İç işler

    private func apply(session: CustomerSessionResponse) {
        accessToken = session.accessToken
        accessExpiresAt = Date.now.addingTimeInterval(TimeInterval(session.expiresIn))
        try? KeychainStore.saveRefreshToken(session.refreshToken)
        apply(account: session.account)
    }

    private func apply(account: CustomerAccount) {
        self.account = account
        if let data = try? JSONEncoder().encode(account) {
            defaults.set(data, forKey: Key.account)
        }
    }

    private func clearLocalSession() {
        accessToken = nil
        accessExpiresAt = .distantPast
        account = nil
        KeychainStore.deleteRefreshToken()
        defaults.removeObject(forKey: Key.account)
    }
}

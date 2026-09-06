import Foundation
import UIKit
import Combine

enum SessionState: Equatable {
    case launching
    case signedOut
    case signedIn
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var state: SessionState = .launching
    @Published private(set) var user: OperationUser?
    @Published private(set) var venues: [Venue] = []
    @Published private(set) var activeVenue: Venue?
    @Published private(set) var accessToken: String?

    private let api: APIClient
    private let activeVenueDefaultsKey = "active-operation-venue-id"
    private var refreshTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    func restore() async {
        do {
            guard let refreshToken = try KeychainStore.refreshToken() else {
                state = .signedOut
                return
            }
            let payload: MobileAuthPayload = try await api.post(
                "/mobile/auth/refresh",
                body: MobileRefreshRequest(refreshToken: refreshToken)
            )
            try persist(payload)
            apply(user: payload.user, venues: payload.venues)
            state = .signedIn
            scheduleRefresh(after: payload.expiresIn)
        } catch {
            clearLocalSession()
        }
    }

    func login(email: String, password: String) async throws {
        let installationID = try KeychainStore.installationID()
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
        try persist(payload)
        apply(user: payload.user, venues: payload.venues)
        state = .signedIn
        scheduleRefresh(after: payload.expiresIn)
    }

    func selectVenue(_ venue: Venue) {
        guard venues.contains(venue) else { return }
        activeVenue = venue
        UserDefaults.standard.set(venue.id, forKey: activeVenueDefaultsKey)
    }

    func logout() async {
        if let refreshToken = try? KeychainStore.refreshToken() {
            let _: EmptyResponse? = try? await api.post(
                "/mobile/auth/logout",
                body: MobileRefreshRequest(refreshToken: refreshToken)
            )
        }
        clearLocalSession()
    }

    private func persist(_ payload: MobileAuthPayload) throws {
        try KeychainStore.saveAccessToken(payload.accessToken)
        try KeychainStore.saveRefreshToken(payload.refreshToken)
        api.setAccessToken(payload.accessToken)
        accessToken = payload.accessToken
    }

    private func scheduleRefresh(after expiresIn: Int) {
        refreshTask?.cancel()
        let delay = Duration.seconds(max(60, expiresIn - 60))
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshSession()
        }
    }

    private func refreshSession() async {
        guard let refreshToken = try? KeychainStore.refreshToken() else {
            clearLocalSession()
            return
        }
        do {
            let payload: MobileAuthPayload = try await api.post(
                "/mobile/auth/refresh",
                body: MobileRefreshRequest(refreshToken: refreshToken)
            )
            try persist(payload)
            apply(user: payload.user, venues: payload.venues)
            scheduleRefresh(after: payload.expiresIn)
        } catch {
            // An interrupted network does not discard a still-valid local session.
            scheduleRefresh(after: 60)
        }
    }

    private func apply(user: OperationUser, venues: [Venue]) {
        let usableVenueIDs = Set(user.venueRoles.filter { $0.role.canUseOperationsApp }.map(\.venueId))
        self.user = user
        self.venues = venues.filter { usableVenueIDs.contains($0.id) }
        let savedVenueID = UserDefaults.standard.integer(forKey: activeVenueDefaultsKey)
        activeVenue = self.venues.first(where: { $0.id == savedVenueID }) ?? self.venues.first
    }

    private func clearLocalSession() {
        refreshTask?.cancel()
        refreshTask = nil
        KeychainStore.deleteSession()
        api.setAccessToken(nil)
        accessToken = nil
        user = nil
        venues = []
        activeVenue = nil
        OperationWidgetSync.clear()
        state = .signedOut
    }
}

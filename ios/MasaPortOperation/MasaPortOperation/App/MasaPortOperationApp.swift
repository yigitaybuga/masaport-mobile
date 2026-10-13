import SwiftUI

@main
struct MasaPortOperationApp: App {
    @StateObject private var session = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(session)
                .tint(MP.brand)
                .task { await session.restore() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Arka planda erişim token'ının süresi dolmuş olabilir; ekranlar yenilenmeden önce tazelenir.
            if newPhase == .active {
                session.sceneDidBecomeActive()
            }
        }
    }
}

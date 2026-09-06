import SwiftUI

@main
struct MasaPortOperationApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(session)
                .tint(MP.brand)
                .task { await session.restore() }
        }
    }
}

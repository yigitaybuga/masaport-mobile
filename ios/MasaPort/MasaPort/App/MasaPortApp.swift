import SwiftUI

@main
struct MasaPortApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(model)
                .tint(MP.brand)
                .task { await model.bootstrap() }
        }
    }
}

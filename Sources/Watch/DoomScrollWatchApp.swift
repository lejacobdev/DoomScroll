import SwiftUI

@main
struct DoomScrollWatchApp: App {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.appBecameActive()
            case .inactive, .background: model.appBecameInactive()
            @unknown default: break
            }
        }
    }
}

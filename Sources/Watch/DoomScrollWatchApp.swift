import SwiftUI

@main
struct DoomScrollWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = ScrollModeController()
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(controller)
                .environmentObject(session)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                controller.appDidBecomeActive()
            default:
                // Covers backgrounding, wrist-down sleep, and water lock:
                // stop motion updates and end any live scroll session.
                controller.appDidResignActive()
            }
        }
    }
}

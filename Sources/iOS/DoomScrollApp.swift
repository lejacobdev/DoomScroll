import SwiftUI

@main
struct DoomScrollApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var session = PhoneSessionManager()
    @StateObject private var dispatcher = ScrollDispatcher()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(dispatcher)
                .onAppear {
                    session.onCommand = { [weak dispatcher, weak settings] command in
                        guard let dispatcher, let settings else { return }
                        dispatcher.handle(command, settings: settings)
                    }
                    session.activate()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Commands that arrived while backgrounded were queued as a
                // net displacement; apply them now.
                dispatcher.applyPendingDelta(settings: settings)
            }
        }
    }
}

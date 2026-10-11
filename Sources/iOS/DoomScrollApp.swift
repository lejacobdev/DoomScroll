import SwiftUI

@main
struct DoomScrollApp: App {
    @StateObject private var model = RelayModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.appBecameActive()
            default: model.appResignedActive()
            }
        }
    }
}

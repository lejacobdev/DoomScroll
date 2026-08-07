import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var dispatcher: ScrollDispatcher

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "list.bullet.rectangle") }
            BrowserView()
                .tabItem { Label("Browser", systemImage: "globe") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .overlay(alignment: .top) {
            StatusBanner()
                .animation(.spring(duration: 0.3), value: dispatcher.isScrolling)
        }
    }
}

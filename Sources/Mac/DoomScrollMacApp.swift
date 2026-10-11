import SwiftUI
import ScrollCore

@main
struct DoomScrollMacApp: App {
    @StateObject private var model = MacModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.scrollModeActive ? "hand.draw.fill" : "hand.draw")
        }
        .menuBarExtraStyle(.window)

        Window("Pair your iPhone", id: "pair") {
            PairView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuView: View {
    @ObservedObject var model: MacModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.scrollModeActive ? "Scroll mode on" : "Scroll mode off",
                  systemImage: model.scrollModeActive ? "hand.draw.fill" : "hand.draw")
                .font(.headline)

            Label(model.clientCount > 0 ? "iPhone connected" : "Waiting for iPhone",
                  systemImage: model.clientCount > 0 ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                .foregroundStyle(model.clientCount > 0 ? .green : .secondary)

            if !model.trusted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("macOS only lets approved apps scroll other apps.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Ask macOS") { model.requestAccessibility() }
                        Button("Open Settings") { model.openPrivacySettings() }
                    }
                }
            }

            Divider()

            Picker("Scroll target", selection: $model.target) {
                Text("Under the pointer").tag(ScrollTarget.pointer)
                Text("iPhone Mirroring window").tag(ScrollTarget.iPhoneMirroring)
            }
            .pickerStyle(.radioGroup)

            if model.target == .iPhoneMirroring && !TargetResolver.isiPhoneMirroringVisible {
                Text("Open the iPhone Mirroring app so there is a window to scroll.")
                    .font(.caption).foregroundStyle(.orange)
            }

            Toggle("Pause", isOn: $model.paused)
            Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin },
                                                 set: { model.setLaunchAtLogin($0) }))

            Divider()

            HStack {
                Button("Pair iPhone…") {
                    openWindow(id: "pair")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}

private struct PairView: View {
    @ObservedObject var model: MacModel
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Pair your iPhone").font(.title2.bold())
            Text("Open DoomScroll on your iPhone, tap “Scan to pair”, and point the camera here.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let image = model.qrImage() {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("This code is a secret. Anyone who can see it can control scrolling on this Mac.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create a new code (unpairs everything)") { confirmReset = true }
                .confirmationDialog("Unpair all devices?", isPresented: $confirmReset) {
                    Button("Create new code", role: .destructive) { model.resetPairing() }
                }
        }
        .padding(24)
        .frame(width: 340)
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var session: PhoneSessionManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Watch app installed") {
                        statusDot(session.isWatchAppInstalled)
                    }
                    LabeledContent("Watch reachable") {
                        statusDot(session.isWatchReachable)
                    }
                    if let last = session.lastCommandAt {
                        LabeledContent("Last command") {
                            Text(last, style: .relative)
                        }
                    }
                }

                Section("Scrolling") {
                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(settings.sensitivity, specifier: "%.1f")×")
                        Slider(value: $settings.sensitivity, in: 0.2...3.0, step: 0.1)
                    }
                    Toggle("Invert vertical", isOn: $settings.invertY)
                    Toggle("Invert horizontal", isOn: $settings.invertX)
                    Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                }

                Section {
                    Toggle("Accessibility scroll fallback", isOn: $settings.useAccessibilityFallback)
                } footer: {
                    Text("When no scroll view is found, page the focused accessibility element instead. This works only inside DoomScroll — iOS does not allow any app to scroll other apps. See LIMITATIONS.md in the repository for the full explanation.")
                }

                Section("How to use") {
                    Label("Open the Feed or Browser tab", systemImage: "1.circle")
                    Label("Double tap on your Watch (watchOS 11+) or press Air Scroll", systemImage: "2.circle")
                    Label("Tilt your wrist to scroll; roll it for horizontal", systemImage: "3.circle")
                    Label("Double tap again to stop", systemImage: "4.circle")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func statusDot(_ ok: Bool) -> some View {
        Circle()
            .fill(ok ? Color.green : Color.orange)
            .frame(width: 10, height: 10)
    }
}

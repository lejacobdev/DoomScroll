import ScrollCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: RelayModel
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Mac") {
                    if let token = model.token {
                        LabeledContent("Paired with", value: token.macName)
                        LabeledContent("Connection") {
                            Label(linkText, systemImage: linkIcon).foregroundStyle(linkColor)
                        }
                        Button("Unpair", role: .destructive) { model.unpair() }
                    } else {
                        Text("On your Mac, open DoomScroll in the menu bar and choose “Pair iPhone…”.")
                            .foregroundStyle(.secondary)
                    }
                    Button(model.token == nil ? "Scan to pair" : "Scan a different Mac") {
                        showScanner = true
                    }
                    if let err = model.scanError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Apple Watch") {
                    LabeledContent("Watch app") {
                        Text(model.watchInstalled ? "Installed" : "Not installed")
                            .foregroundStyle(model.watchInstalled ? .green : .orange)
                    }
                    LabeledContent("Reachable") { Text(model.watchReachable ? "Yes" : "No") }
                }

                Section("Gesture") {
                    Picker("Style", selection: $model.settings.style) {
                        Text("Flick (throw and coast)").tag(ControlStyle.flick)
                        Text("Tilt (hold to scroll)").tag(ControlStyle.tilt)
                    }
                    VStack(alignment: .leading) {
                        Text("Sensitivity  \(model.settings.sensitivity, format: .number.precision(.fractionLength(1)))×")
                        Slider(value: $model.settings.sensitivity, in: ScrollSettings.sensitivityRange)
                    }
                    Toggle("Reverse vertical", isOn: $model.settings.invertY)
                    Toggle("Reverse horizontal", isOn: $model.settings.invertX)
                    Toggle("Haptics on Watch", isOn: $model.settings.hapticsEnabled)
                }

                Section("Scroll target on the Mac") {
                    Picker("Target", selection: $model.settings.target) {
                        Text("Under the pointer").tag(ScrollTarget.pointer)
                        Text("iPhone Mirroring window").tag(ScrollTarget.iPhoneMirroring)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("How to use") {
                    Text("1. Double-tap your fingers (index finger and thumb) to start scrolling.\n2. Flick your wrist to scroll, or tilt it in Tilt style.\n3. Double-tap again to stop.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Keep this app open on your iPhone while you scroll. It relays the Watch's motion to your Mac.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DoomScroll")
        }
        .sheet(isPresented: $showScanner) {
            ZStack(alignment: .topTrailing) {
                QRScannerView { code in
                    model.pair(withScanned: code)
                    showScanner = false
                }
                .ignoresSafeArea()
                Button("Cancel") { showScanner = false }
                    .buttonStyle(.borderedProminent).padding()
            }
        }
    }

    private var linkText: String {
        switch model.linkState {
        case .ready: "Connected"
        case .connecting: "Connecting…"
        case .searching: "Looking for your Mac…"
        case .idle: "Not started"
        }
    }

    private var linkIcon: String {
        model.linkState == .ready ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
    }

    private var linkColor: Color {
        model.linkState == .ready ? .green : .orange
    }
}

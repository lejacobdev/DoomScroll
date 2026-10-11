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

// MARK: - Menu

private struct MenuView: View {
    @ObservedObject var model: MacModel
    @Environment(\.openWindow) private var openWindow

    private var setupComplete: Bool { model.trusted && model.hasPairedDevice }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !setupComplete { checklist }

            VStack(alignment: .leading, spacing: 8) {
                Text("Scroll target").font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TargetTile(title: "Pointer", symbol: "cursorarrow",
                               selected: model.target == .pointer) { model.target = .pointer }
                    TargetTile(title: "iPhone", symbol: "iphone",
                               selected: model.target == .iPhoneMirroring) { model.target = .iPhoneMirroring }
                }
                if model.target == .iPhoneMirroring && !TargetResolver.isiPhoneMirroringVisible {
                    Label("Open the iPhone Mirroring app first.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Divider()

            Toggle("Pause scrolling", isOn: $model.paused)
            Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin },
                                                  set: { model.setLaunchAtLogin($0) }))

            Divider()

            HStack {
                Button {
                    openWindow(id: "pair")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Pair iPhone", systemImage: "qrcode")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.switch)
        .padding(16)
        .frame(width: 310)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.scrollModeActive ? "hand.draw.fill" : "hand.draw")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(model.scrollModeActive ? Color.green.opacity(0.2) : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .foregroundStyle(model.scrollModeActive ? Color.green : Color.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("DoomScroll").font(.system(.headline, design: .rounded, weight: .bold))
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if model.paused { return "Paused" }
        if model.scrollModeActive { return "Scrolling" }
        if model.clientCount > 0 { return "Ready" }
        return model.hasPairedDevice ? "Waiting for your iPhone" : "Not paired yet"
    }

    private var statusColor: Color {
        if model.paused { return .gray }
        if model.scrollModeActive { return .green }
        return model.clientCount > 0 ? .green : .orange
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finish setup").font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            ChecklistRow(done: model.trusted, title: "Allow Accessibility",
                         detail: "Lets DoomScroll scroll other apps.",
                         actionTitle: "Allow") {
                model.requestAccessibility()
                model.openPrivacySettings()
            }
            ChecklistRow(done: model.hasPairedDevice, title: "Pair your iPhone",
                         detail: "Scan a code to connect securely.",
                         actionTitle: "Pair") {
                openWindow(id: "pair")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ChecklistRow: View {
    let done: Bool
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.callout, design: .rounded, weight: .semibold))
                if !done { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !done { Button(actionTitle, action: action).controlSize(.small) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Needs attention")
    }
}

private struct TargetTile: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title).font(.system(.callout, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .background(selected ? Color.primary : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Pair window

private struct PairView: View {
    @ObservedObject var model: MacModel
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Pair your iPhone").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Open DoomScroll on your iPhone and scan this code.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let image = model.qrImage() {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 230, height: 230)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .accessibilityLabel("Pairing QR code")
            }
            if model.clientCount > 0 {
                Label("iPhone connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Text("Keep this code private. Anyone who can see it can scroll your Mac.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create a new code", role: .destructive) { confirmReset = true }
                .buttonStyle(.link)
                .confirmationDialog("Unpair every device?", isPresented: $confirmReset) {
                    Button("Create new code", role: .destructive) { model.resetPairing() }
                } message: {
                    Text("Your iPhone and Watch will need to scan the new code.")
                }
        }
        .padding(28)
        .frame(width: 360)
    }
}

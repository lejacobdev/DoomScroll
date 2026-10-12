import ScrollCore
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: RelayModel
    @State private var confirmUnpair = false
    @State private var showBrowser = false
    @AppStorage("lastScrollApp") private var lastApp = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusHero
                    HStack(spacing: 12) { destinationCard; watchCard }

                    SectionTitle("Gesture")
                    HStack(spacing: 12) {
                        OptionTile(title: "Flick", subtitle: "Snap your wrist",
                                   symbol: "hand.draw", selected: model.settings.style == .flick) {
                            Haptics.select(); model.settings.style = .flick
                        }
                        OptionTile(title: "Tilt", subtitle: "Hold to keep scrolling",
                                   symbol: "rotate.3d", selected: model.settings.style == .tilt) {
                            Haptics.select(); model.settings.style = .tilt
                        }
                    }
                    OptionTile(title: "Phone flick", subtitle: "Flick your iPhone itself. No Watch needed.",
                               symbol: "iphone.radiowaves.left.and.right",
                               selected: model.settings.style == .phone) {
                        Haptics.select(); model.settings.style = .phone
                    }

                    if model.settings.style == .phone { phoneCard }

                    sensitivityCard

                    SectionTitle("Where to scroll")
                    HStack(spacing: 12) {
                        OptionTile(title: "Mac", subtitle: "Any app, over Wi-Fi",
                                   symbol: "laptopcomputer", selected: model.settings.destination == .mac) {
                            Haptics.select(); model.settings.destination = .mac
                        }
                        OptionTile(title: "This iPhone", subtitle: "In the DoomScroll browser. No Mac.",
                                   symbol: "iphone", selected: model.settings.destination == .phone) {
                            Haptics.select(); model.settings.destination = .phone
                        }
                    }

                    if model.settings.destination == .mac {
                        HStack(spacing: 12) {
                            OptionTile(title: "Pointer", subtitle: "Whatever your pointer is over",
                                       symbol: "cursorarrow", selected: model.settings.target == .pointer) {
                                Haptics.select(); model.settings.target = .pointer
                            }
                            OptionTile(title: "iPhone Mirroring", subtitle: "Scroll this iPhone via your Mac",
                                       symbol: "rectangle.on.rectangle", selected: model.settings.target == .iPhoneMirroring) {
                                Haptics.select(); model.settings.target = .iPhoneMirroring
                            }
                        }
                    } else {
                        browserCard
                    }

                    SectionTitle("More")
                    moreCard

                    Text(model.settings.destination == .phone
                         ? "iOS only lets an app scroll its own content, so this scrolls the DoomScroll browser, not Safari or other apps. Keep it open on screen while you scroll."
                         : "Keep DoomScroll open on your iPhone while you scroll. It relays your Watch to your Mac and works best in the foreground.")
                        .font(.captionRounded).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.top, 4)
                }
                .padding(.horizontal, DS.pad)
                .padding(.vertical, 12)
            }
            .background(Color.canvas)
            .navigationTitle("DoomScroll")
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(isPresented: $showBrowser) { BrowserScreen() }
        .sheet(isPresented: Binding(get: { model.phoneCalibration != .idle },
                                    set: { if !$0 { model.cancelPhoneCalibration() } })) {
            PhoneCalibrationSheet(model: model)
        }
        .confirmationDialog("Unpair \(model.token?.macName ?? "this Mac")?",
                            isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { model.unpair() }
        } message: {
            Text("You can pair again any time by scanning the code in the Mac app.")
        }
    }

    // MARK: Hero

    private struct Hero {
        var symbol: String
        var tint: Color
        var title: String
        var subtitle: String
    }

    private var hero: Hero {
        if model.settings.destination == .phone {
            if !model.watchInstalled {
                return Hero(symbol: "applewatch.slash", tint: .warn, title: "Install the Watch app",
                            subtitle: "Open the Watch app on this iPhone and install DoomScroll.")
            }
            if !model.settings.calibrated {
                return Hero(symbol: "wand.and.rays", tint: .warn, title: "Calibrate your wrist",
                            subtitle: "Open DoomScroll on your Watch and follow the prompts.")
            }
            return Hero(symbol: "checkmark", tint: .good, title: "Ready to scroll",
                        subtitle: "Open the browser, then double-tap your fingers on your Watch.")
        }
        if !model.isPaired {
            return Hero(symbol: "laptopcomputer", tint: .ink, title: "Pair your Mac",
                        subtitle: "Scan the code from the DoomScroll Mac app.")
        }
        if model.linkState == .localNetworkDenied {
            return Hero(symbol: "wifi.exclamationmark", tint: .bad, title: "Allow Local Network",
                        subtitle: "DoomScroll needs it to find your Mac. Turn it on in Settings.")
        }
        if model.linkState == .ready {
            if !model.watchInstalled {
                return Hero(symbol: "applewatch.slash", tint: .warn, title: "Install the Watch app",
                            subtitle: "Open the Watch app on this iPhone and install DoomScroll.")
            }
            if !model.settings.calibrated {
                return Hero(symbol: "wand.and.rays", tint: .warn, title: "Calibrate your wrist",
                            subtitle: "Open DoomScroll on your Watch and follow the prompts.")
            }
            return Hero(symbol: "checkmark", tint: .good, title: "Ready to scroll",
                        subtitle: "Double-tap your fingers on your Watch to begin.")
        }
        return Hero(symbol: "antenna.radiowaves.left.and.right", tint: .warn, title: "Looking for your Mac…",
                    subtitle: "Make sure it's awake, on the same Wi-Fi, and DoomScroll is running.")
    }

    private var statusHero: some View {
        Card {
            VStack(spacing: 16) {
                HeroBadge(symbol: hero.symbol, tint: hero.tint, size: 96)
                VStack(spacing: 6) {
                    Text(hero.title).font(.display(26))
                    Text(hero.subtitle).font(.bodyRounded).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if model.settings.destination == .mac && model.linkState == .localNetworkDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.primary)
                } else if model.settings.destination == .phone {
                    Button("Open browser") { showBrowser = true }.buttonStyle(.primary)
                } else if !model.isPaired {
                    Button("Set up") { model.restartOnboarding() }.buttonStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Phone flick

    private var phoneReady: Bool {
        (model.settings.destination == .phone || (model.isPaired && model.linkState == .ready))
            && model.phoneMotionAvailable
    }

    private var phoneCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.phoneScrolling ? "Flicking is on" : "Flick your iPhone")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(phoneHint).font(.captionRounded).foregroundStyle(.secondary)
                Button(model.phoneScrolling ? "Stop" : "Start flicking") { model.togglePhoneScrolling() }
                    .buttonStyle(.primary)
                    .disabled(!phoneReady && !model.phoneScrolling)
                Button(model.settings.phoneCalibrated ? "Recalibrate direction" : "Calibrate direction") {
                    model.startPhoneCalibration()
                }
                .buttonStyle(.secondary)
                .disabled(!model.phoneMotionAvailable)
            }
        }
    }

    private var phoneHint: String {
        if model.settings.destination == .mac {
            if !model.isPaired { return "Pair your Mac first." }
            if model.linkState != .ready { return "Waiting to connect to your Mac." }
        }
        if !model.phoneMotionAvailable { return "This device has no motion sensors." }
        if model.phoneScrolling { return "Tip the top of your phone toward or away from you to scroll. Keep this screen open." }
        if !model.settings.phoneCalibrated { return "Calibrate once so scrolling matches how you hold your phone, then start." }
        return "Hold your phone upright, start, and flick. Keep this screen open while you scroll."
    }

    // MARK: Device cards

    @ViewBuilder
    private var destinationCard: some View {
        if model.settings.destination == .phone {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "iphone").font(.system(size: 22, weight: .semibold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This iPhone")
                            .font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                        HStack(spacing: 6) {
                            StatusDot(color: .good)
                            Text("In-app browser").font(.captionRounded).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            macCard
        }
    }

    private var browserCard: some View {
        Card {
            VStack(spacing: 12) {
                Text("Choose your app")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AppHoneycomb(selected: ScrollApp(rawValue: lastApp)) { app in
                    lastApp = app.rawValue
                    BrowserModel.shared.open(app)
                    showBrowser = true
                }
                Text("Opens the web version in DoomScroll's browser, where your Watch can scroll it. iOS doesn't let any app control the TikTok, Instagram, YouTube or Snapchat apps themselves.")
                    .font(.captionRounded).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var macCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "laptopcomputer").font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.token?.macName ?? "No Mac")
                        .font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusDot(color: macColor)
                        Text(macText).font(.captionRounded).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var watchCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "applewatch").font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Watch").font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusDot(color: model.watchInstalled ? (model.watchReachable ? .good : .warn) : .bad)
                        Text(watchText).font(.captionRounded).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var macColor: Color {
        switch model.linkState {
        case .ready: .good
        case .localNetworkDenied: .bad
        default: model.isPaired ? .warn : .bad
        }
    }

    private var macText: String {
        guard model.isPaired else { return "Not paired" }
        switch model.linkState {
        case .ready: return model.linkViaBluetooth ? "Bluetooth" : "Connected"
        case .connecting: return "Connecting"
        case .localNetworkDenied: return "Blocked"
        default: return "Searching"
        }
    }

    private var watchText: String {
        if !model.watchInstalled { return "Not installed" }
        return model.watchReachable ? "Connected" : "Installed"
    }

    // MARK: Sensitivity

    private var sensitivityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sensitivity").font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                    Text("\(model.settings.sensitivity, format: .number.precision(.fractionLength(1)))×")
                        .font(.display(28)).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Slider(value: $model.settings.sensitivity, in: ScrollSettings.sensitivityRange) { editing in
                    if !editing { Haptics.select() }
                }
                .tint(Color.ink)
                .accessibilityLabel("Sensitivity")
                HStack {
                    Text("Slower"); Spacer(); Text("Faster")
                }
                .font(.captionRounded).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: More

    private var moreCard: some View {
        Card(padding: 4) {
            VStack(spacing: 0) {
                toggleRow("Haptics on Watch", "hand.tap", $model.settings.hapticsEnabled)
                divider
                toggleRow("Reverse vertical", "arrow.up.arrow.down", $model.settings.invertY)
                divider
                toggleRow("Reverse horizontal", "arrow.left.arrow.right", $model.settings.invertX)
                divider
                toggleRow("Reels mode: one flick, one reel", "play.rectangle", $model.settings.reelsMode)
                divider
                toggleRow("Reverse Digital Crown", "digitalcrown.arrow.clockwise", $model.settings.crownReversed)
                divider
                actionRow("Recalibrate wrist", "wand.and.rays") { model.resetCalibration() }
                divider
                actionRow("Show setup guide", "list.bullet.rectangle") { model.restartOnboarding() }
                if model.isPaired {
                    divider
                    actionRow("Unpair Mac", "link.badge.plus", destructive: true) { confirmUnpair = true }
                }
            }
        }
    }

    private var divider: some View {
        Divider().padding(.leading, 56)
    }

    private func toggleRow(_ title: String, _ symbol: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Label {
                Text(title).font(.system(.body, design: .rounded, weight: .medium))
            } icon: {
                Image(systemName: symbol).frame(width: 28)
            }
        }
        .tint(Color.good)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func actionRow(_ title: String, _ symbol: String, destructive: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title).font(.system(.body, design: .rounded, weight: .medium))
                } icon: {
                    Image(systemName: symbol).frame(width: 28)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(destructive ? Color.bad : Color.ink)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

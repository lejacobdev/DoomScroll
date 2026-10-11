import ScrollCore
import SwiftUI

/// First-run flow: Welcome → Mac → Pair → Watch → Calibrate → Done.
struct OnboardingView: View {
    @ObservedObject var model: RelayModel
    @State private var step: Step = .welcome
    @State private var scanAttempt = 0
    @State private var cameraDenied = false
    @State private var rescanning = false
    @Environment(\.openURL) private var openURL

    enum Step: Int, CaseIterable { case welcome, mac, pair, watch, calibrate, done }

    private static let releasesURL = URL(string: "https://github.com/lejacobdev/DoomScroll/releases")!

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, DS.pad)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .id(step)
                    .transition(.opacity.combined(with: .offset(x: 24)))
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(Color.canvas.ignoresSafeArea())
        .animation(.snappy(duration: 0.3), value: step)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 16) {
            Button { go(to: previous) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Color.card, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
            .accessibilityLabel("Back")

            ProgressBar(value: Double(step.rawValue + 1) / Double(Step.allCases.count))
        }
        .padding(.horizontal, DS.pad)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.primary)
                .disabled(!primaryEnabled)
            if let secondary = secondaryTitle {
                Button(secondary) { go(to: next) }
                    .buttonStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.pad)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.canvas)
    }

    // MARK: Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .mac: mac
        case .pair: pair
        case .watch: watch
        case .calibrate: calibrate
        case .done: done
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.display(32)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.bodyRounded).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack { Spacer(); HeroBadge(symbol: "applewatch.watchface", size: 150); Spacer() }
                .padding(.top, 24)
            heading("Scroll anything with a flick of your wrist.",
                    "Control your Mac, and your iPhone through iPhone Mirroring, straight from your Apple Watch.")
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    InfoRow(symbol: "hand.point.up.left.fill", title: "Double-tap to start",
                            subtitle: "Tap your index finger and thumb together twice")
                    InfoRow(symbol: "arrow.up.and.down", title: "Flick to scroll",
                            subtitle: "Snap your wrist and the page glides")
                    InfoRow(symbol: "square.stack.3d.up.fill", title: "Works in every app",
                            subtitle: "Safari, Mail, PDFs, social, anything on your Mac")
                }
            }
        }
    }

    private var mac: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Set up your Mac", "DoomScroll for Mac is a tiny menu bar app that does the actual scrolling.")
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    numbered(1, "Get the Mac app", "Open the link below on your Mac, or send it there.")
                    numbered(2, "Open it", "Look for the hand icon in your menu bar.")
                    numbered(3, "Allow Accessibility", "macOS asks once. This is what lets it scroll other apps.")
                }
            }
            ShareLink(item: Self.releasesURL,
                      subject: Text("DoomScroll for Mac"),
                      message: Text("Download DoomScroll for Mac")) {
                Label("Send link to my Mac", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.secondary)
        }
    }

    private func numbered(_ n: Int, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.inkInverse)
                .frame(width: 30, height: 30)
                .background(Color.ink, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded, weight: .semibold))
                Text(subtitle).font(.captionRounded).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(n). \(title). \(subtitle)")
    }

    private var pair: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Scan the code on your Mac", "Click the DoomScroll icon in your menu bar, then choose Pair iPhone.")
            scannerCard
            if let error = model.scanError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.captionRounded).foregroundStyle(Color.bad)
            }
            if model.isPaired && !rescanning {
                Button("Scan a different Mac") { rescanning = true; scanAttempt += 1 }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var scannerCard: some View {
        ZStack {
            if model.isPaired && !rescanning {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72)).foregroundStyle(Color.good)
                        .symbolEffect(.bounce, value: model.isPaired)
                    Text("Paired with")
                        .font(.captionRounded).foregroundStyle(.secondary)
                    Text(model.token?.macName ?? "your Mac")
                        .font(.titleRounded)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.card)
            } else if cameraDenied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Camera access is off").font(.system(.headline, design: .rounded, weight: .bold))
                    Text("DoomScroll only uses it to read the code on your Mac.")
                        .font(.captionRounded).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.primary).frame(maxWidth: 220)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.card)
            } else {
                QRScannerView(onCode: handleScanned, onPermission: { cameraDenied = !$0 })
                    .id(scanAttempt)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .padding(36)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isPaired && !rescanning ? "Paired" : "QR code scanner")
    }

    private func handleScanned(_ code: String) {
        if model.pair(withScanned: code) {
            rescanning = false
            Task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                if step == .pair { go(to: .watch) }
            }
        } else {
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                scanAttempt += 1
            }
        }
    }

    private var watch: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Open DoomScroll on your Watch", "It installs automatically alongside this app.")
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    statusRow("Watch app installed", done: model.watchInstalled)
                    statusRow("Watch connected", done: model.watchReachable)
                }
            }
            if !model.watchInstalled {
                Card {
                    InfoRow(symbol: "applewatch", title: "Not showing up?",
                            subtitle: "Open the Watch app on this iPhone, find DoomScroll under Available Apps, and tap Install.")
                }
            }
        }
    }

    private var calibrate: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Teach your wrist", "On your Watch, follow the two quick prompts so scrolling matches how you move.")
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    InfoRow(symbol: "arrow.down", title: "Flick the way you want to scroll down")
                    InfoRow(symbol: "arrow.right", title: "Roll the way you want to scroll right")
                }
            }
            Card {
                statusRow("Calibrated", done: model.settings.calibrated)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Spacer(); HeroBadge(symbol: "checkmark", tint: Color.good, size: 150); Spacer() }
                .padding(.top, 24)
            heading("You're all set", "Try it on your Mac. Here's how it works:")
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    InfoRow(symbol: "hand.point.up.left.fill", title: "Double-tap your fingers",
                            subtitle: "Starts and stops scrolling")
                    InfoRow(symbol: "arrow.up.and.down", title: "Flick your wrist",
                            subtitle: "A quick snap throws the page")
                    InfoRow(symbol: "iphone", title: "Keep this app open",
                            subtitle: "It can relay from your pocket for a while, but works best open")
                }
            }
        }
    }

    private func statusRow(_ title: String, done: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.good : Color.softFill).frame(width: 32, height: 32)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Text(title).font(.system(.body, design: .rounded, weight: .semibold))
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Waiting")
    }

    // MARK: Navigation

    private var previous: Step { Step(rawValue: max(0, step.rawValue - 1)) ?? .welcome }
    private var next: Step { Step(rawValue: min(Step.allCases.count - 1, step.rawValue + 1)) ?? .done }

    private func go(to s: Step) {
        Haptics.tap()
        step = s
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .mac: "My Mac is ready"
        case .pair, .watch, .calibrate: "Continue"
        case .done: "Start scrolling"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case .pair: model.isPaired && !rescanning
        case .watch: model.watchInstalled
        case .calibrate: model.settings.calibrated
        default: true
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case .watch where !model.watchInstalled: "Skip for now"
        case .calibrate where !model.settings.calibrated: "Skip for now"
        default: nil
        }
    }

    private func primaryAction() {
        if step == .done {
            Haptics.success()
            model.finishOnboarding()
        } else {
            go(to: next)
        }
    }
}

import ScrollCore
import SwiftUI

extension View {
    /// Binds the system Double Tap (index finger + thumb pinch; Series 9 /
    /// Ultra 2 and later on watchOS 11) to this control.
    @ViewBuilder
    func doubleTapTarget() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

extension View {
    /// Opts a control out of Double Tap, so it only responds to a real press.
    /// watchOS otherwise offers a screen's prominent button to Double Tap.
    @ViewBuilder
    func pressOnly() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction, isEnabled: false)
        } else {
            self
        }
    }
}

/// Big round button in the style of the main one, used for setup and calibration.
private struct RoundActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white).frame(width: 84, height: 84)
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 5).frame(width: 96, height: 96)
                VStack(spacing: 2) {
                    Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
                    Text(title).font(.system(.footnote, design: .rounded, weight: .bold))
                }
                .foregroundStyle(.black)
            }
        }
        .buttonStyle(.plain)
        .pressOnly()
        .accessibilityLabel(title)
    }
}

struct WatchContentView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        Group {
            if !model.hasDestination {
                UnpairedView()
            } else if model.calibration != .idle {
                CalibrationView(model: model)
            } else if model.needsCalibration {
                SetupFlickView(model: model)
            } else {
                MainView(model: model)
            }
        }
        .animation(.snappy, value: model.calibration)
        .animation(.snappy, value: model.scrollMode)
    }
}

// MARK: - Main

private struct MainView: View {
    @ObservedObject var model: WatchModel
    @State private var crown = 0.0
    @State private var holdFired = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                // A touch-and-hold already started calibration; ignore the release.
                if holdFired { holdFired = false } else { model.toggleScrollMode() }
            } label: {
                ZStack {
                    Circle()
                        .fill(model.scrollMode ? Color.green : Color.white)
                        .frame(width: 104, height: 104)
                    Circle()
                        .stroke((model.scrollMode ? Color.green : Color.white).opacity(0.25), lineWidth: 6)
                        .frame(width: 120, height: 120)
                    Image(systemName: model.scrollMode ? "arrow.up.and.down" : "hand.point.up.left.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.black)
                        .symbolEffect(.pulse, isActive: model.scrollMode)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.settings.style == .phone)
            .opacity(model.settings.style == .phone ? 0.35 : 1)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.7).onEnded { _ in
                    holdFired = true
                    model.startCalibration()
                }
            )
            // Only a press toggles scrolling; Double Tap is for liking (the heart below).
            .pressOnly()
            .accessibilityLabel(model.scrollMode ? "Stop scrolling" : "Start scrolling")
            .accessibilityHint("Press to toggle. Touch and hold to recalibrate.")

            VStack(spacing: 2) {
                Text(model.scrollMode ? "Scrolling" : "Ready")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(hint)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !model.scrollMode {
                    Text("Hold the button to recalibrate")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 8) {
                StatusPill(model: model)
                Button { model.like() } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .doubleTapTarget()
                .accessibilityLabel("Like")
                .accessibilityHint("Double-tap your fingers to like what's on screen")
            }
        }
        .padding(.horizontal, 6)
        // Turning the Digital Crown scrolls too, with or without wrist scroll mode.
        .focusable()
        .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000,
                              sensitivity: .medium, isContinuous: false,
                              isHapticFeedbackEnabled: false)
        .onChange(of: crown) { old, new in model.crownRotated(by: new - old) }
    }

    private var hint: String {
        if model.motionUnavailable { return "Motion sensors unavailable" }
        if model.settings.style == .phone { return "Phone mode: flick your iPhone" }
        if model.scrollMode {
            return model.settings.style == .flick ? "Flick your wrist" : "Tilt your wrist"
        }
        return "Press to scroll · double-tap to like"
    }
}

private struct StatusPill: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(.caption2, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        if model.settings.destination == .phone { return model.relayAvailable ? "This iPhone" : "Open iPhone app" }
        switch model.linkState {
        case .ready: return model.token?.macName ?? "Mac"
        case .localNetworkDenied: return "Allow Local Network"
        default: return model.relayAvailable ? "Via iPhone" : "Finding Mac…"
        }
    }

    private var color: Color {
        if model.settings.destination == .phone { return model.relayAvailable ? .green : .orange }
        if model.linkState == .ready { return .green }
        if model.linkState == .localNetworkDenied { return .red }
        return model.relayAvailable ? .yellow : .orange
    }
}

// MARK: - Unpaired

private struct UnpairedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.white)
            Text("Pair on iPhone")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text("Open DoomScroll on your iPhone to connect your Mac, or choose This iPhone.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Calibration

private struct SetupFlickView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.rays")
                .font(.system(size: 32))
            Text("Teach your wrist")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text("Two quick flicks so scrolling matches how you move.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            RoundActionButton(title: "Start", symbol: "hand.point.up.left.fill") {
                model.startCalibration()
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct CalibrationView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        VStack(spacing: 8) {
            switch model.calibration {
            case let .waiting(step):
                prompt(step, warning: nil)
            case let .sameMotion(step):
                prompt(step, warning: "Same motion as step 1. Flick a different way.")
            case let .accepted(step):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(.green)
                Text(step == .down ? "Got it" : "Nice")
                    .font(.system(.headline, design: .rounded, weight: .bold))
            case .done:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44)).foregroundStyle(.green)
                Text("All set")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                RoundActionButton(title: "Done", symbol: "checkmark") {
                    model.finishCalibrationScreen()
                }
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func prompt(_ step: CalibrationSession.Step, warning: String?) -> some View {
        Text(step == .down ? "Step 1 of 2" : "Step 2 of 2")
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
        Image(systemName: step == .down ? "arrow.down" : "arrow.right")
            .font(.system(size: 44, weight: .bold))
            .symbolEffect(.pulse)
        Text(step == .down ? "Flick your wrist the way you want to scroll down"
                           : "Now flick a different way to scroll right")
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
        if let warning {
            Text(warning).font(.system(.caption2, design: .rounded)).foregroundStyle(.orange)
        }
        Button("Cancel") { model.cancelCalibration() }
            .font(.system(.caption2, design: .rounded))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .pressOnly()
    }
}

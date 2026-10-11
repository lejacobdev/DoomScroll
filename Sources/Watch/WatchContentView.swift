import ScrollCore
import SwiftUI

extension View {
    /// Binds the system Double Tap (index finger + thumb pinch; Series 9 /
    /// Ultra 2 and later on watchOS 11) to this control.
    @ViewBuilder
    func doubleTapToToggle() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

struct WatchContentView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        Group {
            if model.token == nil {
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

    var body: some View {
        VStack(spacing: 10) {
            Button { model.toggleScrollMode() } label: {
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
            .doubleTapToToggle()
            .accessibilityLabel(model.scrollMode ? "Stop scrolling" : "Start scrolling")
            .accessibilityHint("Double-tap your fingers to toggle")

            VStack(spacing: 2) {
                Text(model.scrollMode ? "Scrolling" : "Ready")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(hint)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            StatusPill(model: model)
        }
        .padding(.horizontal, 6)
    }

    private var hint: String {
        if model.motionUnavailable { return "Motion sensors unavailable" }
        if model.scrollMode {
            return model.settings.style == .flick ? "Flick your wrist" : "Tilt your wrist"
        }
        return "Double-tap your fingers"
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
        switch model.linkState {
        case .ready: return model.token?.macName ?? "Mac"
        case .localNetworkDenied: return "Allow Local Network"
        default: return model.relayAvailable ? "Via iPhone" : "Finding Mac…"
        }
    }

    private var color: Color {
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
            Text("Open DoomScroll on your iPhone to connect your Mac.")
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
            Button("Start") { model.startCalibration() }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
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
            case let .wrongAxis(step):
                prompt(step, warning: step == .down ? "That looks sideways. Try up or down." : "That looks vertical. Try rolling.")
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
                Button("Done") { model.finishCalibrationScreen() }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
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
                           : "Roll your wrist the way you want to scroll right")
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
        if let warning {
            Text(warning).font(.system(.caption2, design: .rounded)).foregroundStyle(.orange)
        }
        Button("Cancel") { model.cancelCalibration() }
            .font(.system(.caption2, design: .rounded))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }
}

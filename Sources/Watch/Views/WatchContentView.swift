import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var controller: ScrollModeController
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                statusHeader

                Button(action: controller.toggle) {
                    VStack(spacing: 4) {
                        Image(systemName: controller.isScrolling
                              ? "stop.circle.fill"
                              : "hand.tap.fill")
                            .font(.title2)
                        Text(controller.isScrolling ? "Stop" : "Air Scroll")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isScrolling ? .red : .blue)
                .systemDoubleTapShortcut()

                if controller.isScrolling {
                    velocityReadout
                    Text("Tilt your wrist to scroll.\nDouble tap to stop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Double tap (or press the button) to start scrolling the phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if session.sendFailureStreak > 10 {
                    Label("Phone not receiving — open the DoomScroll app on your iPhone",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.isReachable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(session.isReachable ? "iPhone connected" : "iPhone unreachable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var velocityReadout: some View {
        HStack(spacing: 12) {
            Label(String(format: "%+.0f", controller.lastSample.map { $0.rollRate * 100 } ?? 0),
                  systemImage: "arrow.left.arrow.right")
            Label(String(format: "%+.0f", controller.lastSample.map { $0.pitchRate * 100 } ?? 0),
                  systemImage: "arrow.up.arrow.down")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

extension View {
    /// On watchOS 11+ the system Double Tap gesture (index finger + thumb)
    /// triggers this view as the scene's primary action — the only public API
    /// through which third-party apps receive Double Tap. On watchOS 10 the
    /// accelerometer-based DoubleTapDetector is the sole trigger.
    @ViewBuilder
    func systemDoubleTapShortcut() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

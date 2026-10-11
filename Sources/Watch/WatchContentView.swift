import ScrollCore
import SwiftUI

extension View {
    /// Binds the system Double Tap (index finger + thumb pinch, Series 9 /
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
        VStack(spacing: 8) {
            if model.token == nil {
                Image(systemName: "iphone.and.arrow.forward").font(.largeTitle)
                Text("Open DoomScroll on your iPhone and scan the Mac's code.")
                    .font(.footnote).multilineTextAlignment(.center)
            } else {
                Button { model.toggleScrollMode() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: model.scrollMode ? "hand.draw.fill" : "hand.draw")
                            .font(.system(size: 34))
                        Text(model.scrollMode ? "Scrolling" : "Tap to scroll")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                }
                .tint(model.scrollMode ? .green : .blue)
                .buttonStyle(.borderedProminent)
                .doubleTapToToggle()

                Text(statusText).font(.caption2).foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)

                if model.motionUnavailable {
                    Text("Motion sensors unavailable").font(.caption2).foregroundStyle(.red)
                } else if model.scrollMode {
                    Text(model.settings.style == .flick ? "Flick your wrist" : "Tilt your wrist")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Double-tap your fingers to start").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusText: String {
        if model.linkState == .ready { return "Connected to \(model.token?.macName ?? "Mac")" }
        if model.relayAvailable { return "Via iPhone (searching for Mac)" }
        switch model.linkState {
        case .searching, .connecting: return "Looking for your Mac…"
        default: return "Mac not reachable"
        }
    }

    private var statusColor: Color {
        if model.linkState == .ready { return .green }
        return model.relayAvailable ? .yellow : .orange
    }
}

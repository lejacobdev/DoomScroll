import Foundation
import UIKit
import os

/// Bridges incoming `ScrollCommand`s to actual scrolling: velocity math,
/// haptics, background queueing, and the active-session flag the UI observes.
@MainActor
final class ScrollDispatcher: ObservableObject {
    /// True while commands are streaming in; drives the status banner.
    @Published private(set) var isScrolling = false
    @Published private(set) var lastDelta = CGVector.zero

    private let scroller = AccessibilityScroller()
    private var calculator = ScrollVelocityCalculator()
    private let log = Logger(subsystem: "dev.lejacob.doomscroll", category: "dispatcher")

    /// Net displacement accumulated while the app was backgrounded, applied on
    /// return to foreground. Bounded so hours in the background can't build an
    /// absurd jump.
    private var pendingBackgroundDelta = CGVector.zero
    private let maxPendingMagnitude: CGFloat = 3000

    private var idleTimer: Timer?

    func handle(_ command: ScrollCommand, settings: SettingsStore) {
        guard command.isActive else {
            endSession(settings: settings)
            return
        }

        let delta = calculator.delta(for: command,
                                     sensitivity: settings.sensitivity,
                                     invertX: settings.invertX,
                                     invertY: settings.invertY)
        lastDelta = delta

        if UIApplication.shared.applicationState == .active {
            isScrolling = true
            armIdleTimer(settings: settings)
            scroller.scroll(byX: delta.dx, y: delta.dy,
                            allowAccessibilityFallback: settings.useAccessibilityFallback)
            if settings.hapticsEnabled {
                HapticManager.shared.scrollTick()
            }
        } else {
            pendingBackgroundDelta.dx = clampPending(pendingBackgroundDelta.dx + delta.dx)
            pendingBackgroundDelta.dy = clampPending(pendingBackgroundDelta.dy + delta.dy)
        }
    }

    /// Called when the app returns to the foreground.
    func applyPendingDelta(settings: SettingsStore) {
        guard pendingBackgroundDelta != .zero else { return }
        let delta = pendingBackgroundDelta
        pendingBackgroundDelta = .zero
        log.info("Applying queued background scroll: (\(delta.dx), \(delta.dy))")
        scroller.scroll(byX: delta.dx, y: delta.dy,
                        allowAccessibilityFallback: settings.useAccessibilityFallback)
    }

    private func endSession(settings: SettingsStore) {
        guard isScrolling else { return }
        isScrolling = false
        calculator.reset()
        idleTimer?.invalidate()
        if settings.hapticsEnabled {
            HapticManager.shared.sessionEnded()
        }
        log.info("Scroll session ended")
    }

    /// If the Watch dies mid-session (battery, range) the final
    /// `isActive: false` message never arrives; time out instead.
    private func armIdleTimer(settings: SettingsStore) {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endSession(settings: settings) }
        }
    }

    private func clampPending(_ value: CGFloat) -> CGFloat {
        min(max(value, -maxPendingMagnitude), maxPendingMagnitude)
    }
}

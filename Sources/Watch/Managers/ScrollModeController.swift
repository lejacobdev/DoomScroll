import Foundation
import SwiftUI
import WatchKit
import os

/// State machine for scroll mode on the Watch: toggled by double tap, streams
/// gyro-derived velocities to the iPhone while active.
@MainActor
final class ScrollModeController: ObservableObject {
    @Published private(set) var isScrolling = false
    @Published private(set) var lastSample: MotionService.GyroSample?

    private let motion = MotionService()
    private let session = WatchSessionManager.shared
    private let log = Logger(subsystem: "dev.lejacob.doomscroll.watchkitapp",
                             category: "scrollmode")

    /// Baseline mapping from rad/s to points-per-second. The iPhone applies
    /// the user-configurable sensitivity multiplier on top of this.
    private let velocityScale = 600.0

    init() {
        motion.tapDetector.onDoubleTap = { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
        motion.onGyroSample = { [weak self] sample in
            Task { @MainActor in self?.handle(sample) }
        }
    }

    func appDidBecomeActive() {
        session.activate()
        motion.start()
    }

    /// Streaming must not continue with the app backgrounded or the wrist
    /// down: stop everything and tell the phone the session ended.
    func appDidResignActive() {
        if isScrolling { setScrolling(false) }
        motion.stop()
    }

    func toggle() { setScrolling(!isScrolling) }

    private func setScrolling(_ active: Bool) {
        guard isScrolling != active else { return }
        isScrolling = active
        motion.gyroStreamingEnabled = active
        WKInterfaceDevice.current().play(active ? .start : .stop)
        if active {
            session.resetFailureStreak()
            log.info("Scroll mode ON")
        } else {
            lastSample = nil
            session.send(ScrollCommand(velocityX: 0, velocityY: 0, isActive: false))
            log.info("Scroll mode OFF")
        }
    }

    private func handle(_ sample: MotionService.GyroSample) {
        guard isScrolling else { return }
        lastSample = sample
        // Tilting the watch face away from you scrolls the phone's content
        // down; either axis can be inverted in the iPhone app's Settings.
        session.send(ScrollCommand(
            velocityX: sample.rollRate * velocityScale,
            velocityY: sample.pitchRate * velocityScale,
            isActive: true,
            timestamp: sample.timestamp
        ))
    }
}

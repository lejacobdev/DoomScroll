import CoreMotion
import Foundation

/// Detects a rapid double tap (index finger + thumb, or a physical tap on the
/// wrist) from user-acceleration spikes.
///
/// This is the fallback path for watchOS 10: the system Double Tap gesture is
/// not delivered to third-party code there. On watchOS 11+ the toggle button
/// also carries `.handGestureShortcut(.primaryAction)`, so the real system
/// gesture triggers it directly and this detector is a redundant backup.
final class DoubleTapDetector {
    /// Peak user-acceleration magnitude (in g) that counts as a tap.
    var tapThreshold: Double = 0.7
    /// Two peaks closer than this are one tap "ringing", not two taps.
    var minInterval: TimeInterval = 0.10
    /// Two peaks farther apart than this are separate single taps.
    var maxInterval: TimeInterval = 0.45
    /// Ignore all peaks for this long after a successful double tap so a burst
    /// of taps toggles the mode once, not repeatedly.
    var refractoryPeriod: TimeInterval = 0.8

    private var lastPeakAt: TimeInterval = 0
    private var lastTriggerAt: TimeInterval = 0

    var onDoubleTap: (() -> Void)?

    func process(userAcceleration a: CMAcceleration, at time: TimeInterval) {
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        guard magnitude >= tapThreshold else { return }
        guard time - lastTriggerAt >= refractoryPeriod else { return }

        let sincePeak = time - lastPeakAt
        if sincePeak >= minInterval && sincePeak <= maxInterval {
            lastTriggerAt = time
            lastPeakAt = 0
            onDoubleTap?()
        } else if sincePeak > maxInterval {
            lastPeakAt = time
        }
        // Peaks inside minInterval are ringing from the previous spike;
        // keep the original peak time so the window doesn't slide.
    }

    func reset() {
        lastPeakAt = 0
    }
}

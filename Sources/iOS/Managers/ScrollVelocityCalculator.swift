import Foundation
import CoreGraphics

/// Turns a stream of `ScrollCommand` velocities into per-tick scroll deltas:
/// applies sensitivity, axis inversion, exponential smoothing, and clamping.
struct ScrollVelocityCalculator {
    /// Hard cap on velocity after sensitivity, in points/second.
    private let maxVelocity: Double = 6000
    /// Exponential smoothing factor (0 = raw input, 1 = frozen). Smooths out
    /// WatchConnectivity jitter without adding noticeable lag at 20 Hz.
    private let smoothing = 0.35

    private var smoothedX: Double = 0
    private var smoothedY: Double = 0
    private var lastCommandAt: TimeInterval?

    /// Computes the point delta to scroll for this command. `dt` is derived
    /// from real inter-arrival time so dropped frames scroll farther rather
    /// than slower, but is clamped so a long stall can't cause a huge jump.
    mutating func delta(for command: ScrollCommand,
                        sensitivity: Double,
                        invertX: Bool,
                        invertY: Bool) -> CGVector {
        let now = Date().timeIntervalSince1970
        let rawDt = lastCommandAt.map { now - $0 } ?? 0.05
        let dt = min(max(rawDt, 0.02), 0.1)
        lastCommandAt = now

        var vx = command.velocityX * sensitivity * (invertX ? -1 : 1)
        var vy = command.velocityY * sensitivity * (invertY ? -1 : 1)
        vx = min(max(vx, -maxVelocity), maxVelocity)
        vy = min(max(vy, -maxVelocity), maxVelocity)

        smoothedX = smoothedX * smoothing + vx * (1 - smoothing)
        smoothedY = smoothedY * smoothing + vy * (1 - smoothing)

        return CGVector(dx: smoothedX * dt, dy: smoothedY * dt)
    }

    mutating func reset() {
        smoothedX = 0
        smoothedY = 0
        lastCommandAt = nil
    }
}

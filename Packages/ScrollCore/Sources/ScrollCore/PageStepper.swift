import Foundation

/// Turns scroll input into whole-page steps, for full-screen vertical feeds
/// (Reels, Shorts) where one gesture should move exactly one video.
///
/// A flick steps once. Continuous input (Crown, tilt) is summed into distance
/// and steps each time enough has built up. After a step, input is ignored for
/// `cooldown` so the page can finish moving before the next step.
public struct PageStepper: Sendable {
    /// Smallest fling (points/s) that counts as a deliberate flick.
    public var flingThreshold = 400.0
    /// Continuous scroll distance (points) that adds up to one step.
    public var distancePerStep = 160.0
    public var cooldown: TimeInterval = 0.5

    private var blockedUntil: TimeInterval = -.infinity
    private var accumulated = 0.0
    private var lastScrollAt: TimeInterval?

    public init() {}

    /// Returns +1 for the next page (scroll down), -1 for the previous page, 0 for none yet.
    public mutating func handle(_ message: WireMessage, at t: TimeInterval) -> Int {
        switch message {
        case let .fling(vx, vy):
            let v = Double(vy)
            guard t >= blockedUntil, abs(v) >= flingThreshold, abs(v) >= abs(Double(vx)) else { return 0 }
            return fire(v > 0 ? 1 : -1, at: t)

        case let .scroll(dx, dy):
            if dx == 0 && dy == 0 {
                accumulated = 0
                lastScrollAt = nil
                return 0
            }
            let dt = lastScrollAt.map { min(max(t - $0, 0), 0.1) } ?? 0.05
            lastScrollAt = t
            guard t >= blockedUntil else { return 0 }
            accumulated += Double(dy) * dt
            guard abs(accumulated) >= distancePerStep else { return 0 }
            return fire(accumulated > 0 ? 1 : -1, at: t)

        case let .nudge(_, dy):
            guard t >= blockedUntil else { return 0 }
            accumulated += Double(dy)
            guard abs(accumulated) >= distancePerStep else { return 0 }
            return fire(accumulated > 0 ? 1 : -1, at: t)

        case .mode:
            accumulated = 0
            lastScrollAt = nil
            return 0

        case .like, .ping:
            return 0
        }
    }

    private mutating func fire(_ direction: Int, at t: TimeInterval) -> Int {
        blockedUntil = t + cooldown
        accumulated = 0
        return direction
    }
}

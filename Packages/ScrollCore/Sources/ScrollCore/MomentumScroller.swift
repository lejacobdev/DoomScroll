import Foundation

/// Mac-side scroll physics. Combines a continuously-held velocity (tilt
/// style) with decaying momentum (flick style) and yields whole-pixel deltas.
public struct MomentumScroller: Sendable {
    public var decayTime: TimeInterval = 0.45
    public var stopSpeed: Double = 20
    public var maxSpeed: Double = 9000
    /// A continuous command that stops arriving (dropped link) must not scroll forever.
    public var continuousTimeout: TimeInterval = 0.25

    private var momentumX = 0.0
    private var momentumY = 0.0
    private var contX = 0.0
    private var contY = 0.0
    private var lastContinuousAt: TimeInterval = -.infinity
    private var carryX = 0.0
    private var carryY = 0.0
    /// Distance from `nudge` that has not been applied yet.
    private var queuedX = 0.0
    private var queuedY = 0.0
    /// How quickly queued nudge distance is applied (time constant, seconds).
    public var nudgeSmoothing: TimeInterval = 0.03

    public init() {}

    public var isIdle: Bool {
        abs(momentumX) < stopSpeed && abs(momentumY) < stopSpeed && contX == 0 && contY == 0
            && queuedX == 0 && queuedY == 0
    }

    /// Adds scroll distance (points) to apply right away, spread over a few
    /// milliseconds so it looks smooth. Stops the moment the distance is used up.
    public mutating func nudge(dx: Double, dy: Double) {
        queuedX = max(-20_000, min(20_000, queuedX + dx))
        queuedY = max(-20_000, min(20_000, queuedY + dy))
    }

    public mutating func setContinuous(dx: Double, dy: Double, at t: TimeInterval) {
        contX = dx
        contY = dy
        lastContinuousAt = t
    }

    public mutating func fling(vx: Double, vy: Double) {
        momentumX = clamp(momentumX * 0.5 + vx)
        momentumY = clamp(momentumY * 0.5 + vy)
    }

    public mutating func stop() {
        momentumX = 0; momentumY = 0
        contX = 0; contY = 0
        carryX = 0; carryY = 0
        queuedX = 0; queuedY = 0
    }

    /// Advance by `dt` seconds ending at time `t`; returns whole-pixel deltas.
    public mutating func tick(dt: TimeInterval, at t: TimeInterval) -> (dx: Int, dy: Int) {
        if t - lastContinuousAt > continuousTimeout {
            contX = 0
            contY = 0
        }
        let decay = exp(-dt / decayTime)
        momentumX *= decay
        momentumY *= decay
        if abs(momentumX) < stopSpeed { momentumX = 0 }
        if abs(momentumY) < stopSpeed { momentumY = 0 }

        carryX += (momentumX + contX) * dt
        carryY += (momentumY + contY) * dt

        let share = 1 - exp(-dt / nudgeSmoothing)
        var stepX = queuedX * share
        var stepY = queuedY * share
        if abs(queuedX - stepX) < 0.5 { stepX = queuedX }
        if abs(queuedY - stepY) < 0.5 { stepY = queuedY }
        queuedX -= stepX
        queuedY -= stepY
        carryX += stepX
        carryY += stepY
        let ix = Int(carryX.rounded(.towardZero))
        let iy = Int(carryY.rounded(.towardZero))
        carryX -= Double(ix)
        carryY -= Double(iy)
        return (ix, iy)
    }

    private func clamp(_ v: Double) -> Double {
        max(-maxSpeed, min(maxSpeed, v))
    }
}

import Foundation

/// Turns Digital Crown rotation into scroll commands.
///
/// The crown reports small rotation deltas many times a second. Sending each one
/// would flood the link, so deltas are summed and sent at most every
/// `sendInterval` as a continuous velocity. That tracks the crown 1:1 (distance
/// is proportional to rotation) and stops as soon as the crown does.
public struct CrownScroller: Sendable {
    /// Scroll points per unit of crown rotation, before the sensitivity setting.
    public var pointsPerUnit: Double = 250
    public var sendInterval: TimeInterval = 0.05
    public var maxSpeed: Double = 9000

    private var pending = 0.0
    private var lastSend: TimeInterval = -.infinity
    private var moving = false

    public init() {}

    /// Feed one crown delta. Returns a scroll to send now, or nil if one isn't due yet.
    public mutating func rotate(by delta: Double, at t: TimeInterval,
                                sensitivity: Double, reversed: Bool) -> WireMessage? {
        pending += reversed ? -delta : delta
        guard t - lastSend >= sendInterval else { return nil }
        let dt = moving ? min(max(t - lastSend, sendInterval), 0.2) : sendInterval
        let speed = pending * pointsPerUnit * sensitivity / dt
        let v = Int(max(-maxSpeed, min(maxSpeed, speed)).rounded())
        guard v != 0 else { return nil }
        pending = 0
        lastSend = t
        moving = true
        return .scroll(dx: 0, dy: v)
    }

    /// Call when the crown has stopped turning. Returns the stop to send, once.
    public mutating func idle() -> WireMessage? {
        guard moving else { return nil }
        moving = false
        pending = 0
        return .scroll(dx: 0, dy: 0)
    }
}

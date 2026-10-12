import Foundation

/// Turns Digital Crown rotation into scroll distance.
///
/// The crown reports small rotation deltas many times a second. Sending each one
/// would flood the link, so deltas are summed and sent at most every
/// `sendInterval` as a distance. The receiver applies that distance right away,
/// so scrolling starts with the first turn and stops with the last one: there is
/// no speed to hold or release, and no distance is lost.
public struct CrownScroller: Sendable {
    /// Scroll points per unit of crown rotation, before the sensitivity setting.
    public var pointsPerUnit: Double = 250
    public var sendInterval: TimeInterval = 0.03
    /// Largest distance in one message, so a fast spin can't jump a huge amount.
    public var maxPointsPerMessage = 600

    private var pending = 0.0
    private var lastSend: TimeInterval = -.infinity

    public init() {}

    /// Feed one crown delta. Returns a scroll to send now, or nil if one isn't due yet.
    public mutating func rotate(by delta: Double, at t: TimeInterval,
                                sensitivity: Double, reversed: Bool) -> WireMessage? {
        pending += (reversed ? -delta : delta) * pointsPerUnit * sensitivity
        guard t - lastSend >= sendInterval else { return nil }
        return take(at: t)
    }

    /// Call shortly after the crown stops turning. Sends whatever distance is still waiting.
    public mutating func idle() -> WireMessage? {
        defer { pending = 0 }
        return take(at: lastSend)
    }

    private mutating func take(at t: TimeInterval) -> WireMessage? {
        let limit = Double(maxPointsPerMessage)
        let whole = max(-limit, min(limit, pending)).rounded(.towardZero)
        guard whole != 0 else { return nil }
        pending -= whole
        lastSend = t
        return .nudge(dx: 0, dy: Int(whole))
    }
}

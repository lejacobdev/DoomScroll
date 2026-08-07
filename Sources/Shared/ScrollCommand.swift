import Foundation

/// Wire format for Watch → iPhone scroll messages sent over WatchConnectivity.
/// Keys are flat strings because `WCSession.sendMessage` requires a
/// property-list dictionary.
struct ScrollCommand: Equatable {
    static let commandName = "scroll"

    /// Receiver drops commands older than this so a WatchConnectivity stall
    /// never replays a stale burst of motion.
    static let staleInterval: TimeInterval = 0.5

    /// Normalized velocity in points-per-second, before the iPhone-side
    /// sensitivity multiplier is applied.
    var velocityX: Double
    var velocityY: Double
    /// `false` marks the final message of a scroll session (mode exited).
    var isActive: Bool
    var timestamp: TimeInterval

    init(velocityX: Double, velocityY: Double, isActive: Bool,
         timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.isActive = isActive
        self.timestamp = timestamp
    }

    var dictionary: [String: Any] {
        [
            "command": Self.commandName,
            "velocityX": velocityX,
            "velocityY": velocityY,
            "isActive": isActive,
            "timestamp": timestamp,
        ]
    }

    /// Numeric values cross WatchConnectivity as NSNumber, so decode through
    /// NSNumber rather than casting to Double directly.
    init?(dictionary: [String: Any]) {
        guard dictionary["command"] as? String == Self.commandName,
              let vx = (dictionary["velocityX"] as? NSNumber)?.doubleValue,
              let vy = (dictionary["velocityY"] as? NSNumber)?.doubleValue,
              let active = (dictionary["isActive"] as? NSNumber)?.boolValue,
              let ts = (dictionary["timestamp"] as? NSNumber)?.doubleValue
        else { return nil }
        self.init(velocityX: vx, velocityY: vy, isActive: active, timestamp: ts)
    }

    var age: TimeInterval { Date().timeIntervalSince1970 - timestamp }
    var isStale: Bool { age > Self.staleInterval }
}

import Foundation

/// Where the Watch's scroll commands end up.
public enum ScrollDestination: Int, Codable, Sendable, CaseIterable {
    /// Relay to the paired Mac, which scrolls any app (or the iPhone Mirroring window).
    case mac = 0
    /// Scroll the DoomScroll browser on this iPhone. No Mac involved. iOS does not
    /// let one app scroll another, so this only reaches content inside DoomScroll.
    case phone = 1
}

/// User settings, edited on the iPhone and synced to the Watch.
public struct ScrollSettings: Codable, Equatable, Sendable {
    public var style: ControlStyle = .flick
    public var sensitivity: Double = 1.0
    public var invertX = false
    public var invertY = false
    public var target: ScrollTarget = .pointer
    public var destination: ScrollDestination = .mac
    public var hapticsEnabled = true
    /// Flips the Digital Crown scroll direction.
    public var crownReversed = false
    /// In the DoomScroll browser, one flick moves exactly one reel instead of free scrolling.
    public var reelsMode = true
    /// Set once the user has demonstrated which way they scroll.
    public var calibrated = false

    /// The iPhone has its own axes and signs, so it calibrates separately from the Watch.
    public var phoneInvertX = false
    public var phoneInvertY = false
    public var phoneCalibrated = false

    public init() {}

    /// Missing keys fall back to defaults, so settings saved by an older build keep
    /// working instead of silently resetting when a field is added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScrollSettings()
        style = try c.decodeIfPresent(ControlStyle.self, forKey: .style) ?? d.style
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        invertX = try c.decodeIfPresent(Bool.self, forKey: .invertX) ?? d.invertX
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? d.invertY
        target = try c.decodeIfPresent(ScrollTarget.self, forKey: .target) ?? d.target
        destination = try c.decodeIfPresent(ScrollDestination.self, forKey: .destination) ?? d.destination
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        crownReversed = try c.decodeIfPresent(Bool.self, forKey: .crownReversed) ?? d.crownReversed
        reelsMode = try c.decodeIfPresent(Bool.self, forKey: .reelsMode) ?? d.reelsMode
        calibrated = try c.decodeIfPresent(Bool.self, forKey: .calibrated) ?? d.calibrated
        phoneInvertX = try c.decodeIfPresent(Bool.self, forKey: .phoneInvertX) ?? d.phoneInvertX
        phoneInvertY = try c.decodeIfPresent(Bool.self, forKey: .phoneInvertY) ?? d.phoneInvertY
        phoneCalibrated = try c.decodeIfPresent(Bool.self, forKey: .phoneCalibrated) ?? d.phoneCalibrated
    }

    public static let sensitivityRange: ClosedRange<Double> = 0.4...2.5

    public var processorConfig: ProcessorConfig {
        var c = ProcessorConfig()
        c.style = style
        c.sensitivity = min(max(sensitivity, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound)
        c.invertX = invertX
        c.invertY = invertY
        return c
    }

    /// Flick processing tuned for the iPhone: always the flick algorithm, with the phone's own signs.
    public var phoneProcessorConfig: ProcessorConfig {
        var c = processorConfig
        c.style = .flick
        c.invertX = phoneInvertX
        c.invertY = phoneInvertY
        return c
    }
}

/// Keys of the WatchConnectivity dictionaries. One place so both sides agree.
public enum WCKey {
    public static let settings = "settings"       // JSON of ScrollSettings (application context)
    public static let pairing = "pairing"         // pairing URL string (application context)
    public static let type = "t"                  // live message: "scroll" | "fling" | "mode" | "ping"
    public static let a = "a"
    public static let b = "b"

    public static func dictionary(for message: WireMessage) -> [String: Any] {
        let (a, b): (Int, Int)
        let t: String
        switch message {
        case let .scroll(dx, dy): (t, a, b) = ("scroll", dx, dy)
        case let .fling(vx, vy): (t, a, b) = ("fling", vx, vy)
        case let .mode(active, target): (t, a, b) = ("mode", active ? 1 : 0, target.rawValue)
        case .ping: (t, a, b) = ("ping", 0, 0)
        }
        return [type: t, Self.a: a, Self.b: b]
    }

    public static func message(from d: [String: Any]) -> WireMessage? {
        guard let t = d[type] as? String,
              let a = (d[Self.a] as? NSNumber)?.intValue,
              let b = (d[Self.b] as? NSNumber)?.intValue else { return nil }
        switch t {
        case "scroll": return .scroll(dx: a, dy: b)
        case "fling": return .fling(vx: a, vy: b)
        case "mode":
            guard let target = ScrollTarget(rawValue: b) else { return nil }
            return .mode(active: a != 0, target: target)
        case "ping": return .ping
        default: return nil
        }
    }
}

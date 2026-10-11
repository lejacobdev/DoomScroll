import Foundation

/// Learns which wrist motion the user means by "scroll down" and
/// "scroll right". Wrist side, crown side and personal preference all change
/// the sign of the raw rotation, so instead of guessing we ask the user to
/// demonstrate it once.
public final class CalibrationSession {
    public enum Step: Int, Sendable, CaseIterable {
        /// "Flick your wrist the way you want to scroll DOWN."
        case down
        /// "Roll your wrist the way you want to scroll RIGHT."
        case right
    }

    public enum Outcome: Equatable, Sendable {
        case none
        /// A flick on the expected axis was recorded; move to the next step.
        case accepted(Step)
        /// A flick happened, but on the other axis. Ask the user to retry.
        case wrongAxis(expected: Step)
        case finished(invertX: Bool, invertY: Bool)
    }

    public private(set) var step: Step? = .down
    private var vertical = AxisFlick()
    private var horizontal = AxisFlick()
    private var invertY = false
    private var invertX = false
    private let config: ProcessorConfig

    public init() {
        var c = ProcessorConfig()
        // Slightly easier to trigger than live scrolling: this is a deliberate, one-off gesture.
        c.flickStartRate = 2.5
        c.flickMinAngle = 0.2
        c.sensitivity = 1
        self.config = c
    }

    public var isFinished: Bool { step == nil }

    public func process(_ s: MotionSample) -> Outcome {
        guard let expected = step else { return .none }
        let v = vertical.step(rate: s.pitchRate, t: s.t, config: config)
        let h = horizontal.step(rate: s.rollRate, t: s.t, config: config)
        guard v != nil || h != nil else { return .none }

        // If both fired, the stronger one is what the user meant.
        let vertWins = abs(v ?? 0) >= abs(h ?? 0)
        let onVerticalAxis = v != nil && vertWins
        let flickAxis: Step = onVerticalAxis ? .down : .right
        guard flickAxis == expected else { return .wrongAxis(expected: expected) }

        switch expected {
        case .down:
            // Positive vertical rate already means "down"; negative means the user's
            // preferred direction is the opposite, so scrolling must be inverted.
            invertY = (v ?? 0) < 0
            step = .right
            return .accepted(.down)
        case .right:
            invertX = (h ?? 0) < 0
            step = nil
            return .finished(invertX: invertX, invertY: invertY)
        }
    }

    public func restart() {
        step = .down
        vertical = AxisFlick()
        horizontal = AxisFlick()
        invertX = false
        invertY = false
    }
}

/// Small control messages the Watch and iPhone exchange (not scroll data).
public enum ControlMessage: Equatable, Sendable {
    case calibrationResult(invertX: Bool, invertY: Bool)

    public var dictionary: [String: Any] {
        switch self {
        case let .calibrationResult(x, y):
            return [WCKey.type: "cal_result", WCKey.a: x ? 1 : 0, WCKey.b: y ? 1 : 0]
        }
    }

    public init?(dictionary d: [String: Any]) {
        guard let t = d[WCKey.type] as? String,
              let a = (d[WCKey.a] as? NSNumber)?.intValue,
              let b = (d[WCKey.b] as? NSNumber)?.intValue else { return nil }
        switch t {
        case "cal_result": self = .calibrationResult(invertX: a != 0, invertY: b != 0)
        default: return nil
        }
    }
}

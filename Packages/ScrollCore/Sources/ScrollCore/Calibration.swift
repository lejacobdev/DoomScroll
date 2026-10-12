import Foundation

/// Learns which wrist motion the user means by "scroll down" and
/// "scroll right". Wrist side, crown side and personal preference all change
/// the sign of the raw rotation, and some people flick sideways for "down", so
/// instead of guessing we ask the user to demonstrate both once.
///
/// Any flick is accepted for either step. The only thing that is rejected is
/// the second flick being the same kind of motion as the first, because then
/// there is no way to tell down from right.
public final class CalibrationSession {
    public enum Step: Int, Sendable, CaseIterable {
        /// "Flick your wrist to scroll DOWN."
        case down
        /// "Flick a different way to scroll RIGHT."
        case right
    }

    public enum Outcome: Equatable, Sendable {
        case none
        /// A flick was recorded; move to the next step.
        case accepted(Step)
        /// The second flick was the same kind of motion as the first. Ask the user to try another.
        case sameMotion(expected: Step)
        case finished(invertX: Bool, invertY: Bool, swapAxes: Bool)
    }

    public private(set) var step: Step? = .down
    private var vertical = AxisFlick()
    private var horizontal = AxisFlick()
    private var firstOnVertical = true
    private var firstSign = 1.0
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
        let onVertical = v != nil && abs(v ?? 0) >= abs(h ?? 0)
        let signed = onVertical ? (v ?? 0) : (h ?? 0)

        switch expected {
        case .down:
            firstOnVertical = onVertical
            firstSign = signed
            step = .right
            return .accepted(.down)
        case .right:
            guard onVertical != firstOnVertical else { return .sameMotion(expected: .right) }
            // The first flick drives "down" and the second drives "right". When the first was
            // the sideways motion, the axes swap roles. A negative rate means the user's
            // preferred direction is the opposite, so that direction is inverted.
            step = nil
            return .finished(invertX: signed < 0, invertY: firstSign < 0, swapAxes: !firstOnVertical)
        }
    }

    public func restart() {
        step = .down
        vertical = AxisFlick()
        horizontal = AxisFlick()
        firstOnVertical = true
        firstSign = 1
    }
}

/// Small control messages the Watch and iPhone exchange (not scroll data).
public enum ControlMessage: Equatable, Sendable {
    case calibrationResult(invertX: Bool, invertY: Bool, swapAxes: Bool)

    public var dictionary: [String: Any] {
        switch self {
        case let .calibrationResult(x, y, swap):
            return [WCKey.type: "cal_result", WCKey.a: x ? 1 : 0, WCKey.b: y ? 1 : 0, WCKey.c: swap ? 1 : 0]
        }
    }

    public init?(dictionary d: [String: Any]) {
        guard let t = d[WCKey.type] as? String,
              let a = (d[WCKey.a] as? NSNumber)?.intValue,
              let b = (d[WCKey.b] as? NSNumber)?.intValue else { return nil }
        switch t {
        case "cal_result":
            // `c` is missing in messages from older builds, which never swapped axes.
            let c = (d[WCKey.c] as? NSNumber)?.intValue ?? 0
            self = .calibrationResult(invertX: a != 0, invertY: b != 0, swapAxes: c != 0)
        default: return nil
        }
    }
}

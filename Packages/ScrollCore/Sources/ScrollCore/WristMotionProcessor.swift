import Foundation

public struct MotionSample: Sendable {
    public var t: TimeInterval
    /// Attitude in radians. Pitch: wrist tilting the watch face toward/away from you.
    public var pitch: Double
    /// Roll: rotating the forearm.
    public var roll: Double
    /// Angular rates in rad/s on the same axes.
    public var pitchRate: Double
    public var rollRate: Double

    public init(t: TimeInterval, pitch: Double, roll: Double, pitchRate: Double, rollRate: Double) {
        self.t = t
        self.pitch = pitch
        self.roll = roll
        self.pitchRate = pitchRate
        self.rollRate = rollRate
    }
}

public enum ControlStyle: String, Codable, Sendable, CaseIterable {
    /// A quick wrist snap throws the page and it coasts to a stop.
    case flick
    /// Holding the wrist tilted scrolls continuously, like a joystick.
    case tilt
    /// Flicking the iPhone itself, using its gyroscope. The Watch is not involved.
    case phone
}

public struct ProcessorConfig: Sendable, Equatable {
    public var style: ControlStyle = .flick
    public var sensitivity: Double = 1.0
    public var invertX = false
    public var invertY = false

    // Tilt style
    public var deadzone: Double = 0.14       // rad (~8 deg)
    public var fullScale: Double = 0.61      // rad (~35 deg)
    public var maxTiltVelocity: Double = 2400 // points/s

    // Flick style
    public var flickStartRate: Double = 3.0   // rad/s
    public var flickEndRate: Double = 1.2
    public var flickMaxDuration: TimeInterval = 0.35
    public var flickMinAngle: Double = 0.25   // rad
    public var flickCooldown: TimeInterval = 0.35
    public var flickGain: Double = 600        // points/s per rad/s of peak rate
    public var maxFlickVelocity: Double = 8000

    public init() {}
}

public enum ProcessorOutput: Equatable, Sendable {
    case scroll(dx: Int, dy: Int)
    case fling(vx: Int, vy: Int)
}

/// Turns raw wrist motion into scroll commands. Pure and deterministic so it
/// can be unit-tested without a watch.
public final class WristMotionProcessor {
    public var config: ProcessorConfig

    private var basePitch = 0.0
    private var baseRoll = 0.0
    private var pitchFlick = AxisFlick()
    private var rollFlick = AxisFlick()
    private var lastEmittedZero = true

    public init(config: ProcessorConfig = ProcessorConfig()) {
        self.config = config
    }

    /// Captures the neutral wrist pose; call when scroll mode turns on.
    public func begin(neutralPitch: Double, neutralRoll: Double) {
        basePitch = neutralPitch
        baseRoll = neutralRoll
        pitchFlick = AxisFlick()
        rollFlick = AxisFlick()
        lastEmittedZero = true
    }

    public func process(_ s: MotionSample) -> [ProcessorOutput] {
        switch config.style {
        case .tilt: return processTilt(s)
        case .flick, .phone: return processFlick(s)
        }
    }

    // MARK: Tilt

    private func processTilt(_ s: MotionSample) -> [ProcessorOutput] {
        let vy = tiltVelocity(s.pitch - basePitch)
        let vx = tiltVelocity(s.roll - baseRoll)
        let dx = Int((signed(vx, invert: config.invertX)).rounded())
        let dy = Int((signed(vy, invert: config.invertY)).rounded())
        if dx == 0 && dy == 0 {
            // Send exactly one zero so the receiver stops, then stay quiet.
            if lastEmittedZero { return [] }
            lastEmittedZero = true
            return [.scroll(dx: 0, dy: 0)]
        }
        lastEmittedZero = false
        return [.scroll(dx: dx, dy: dy)]
    }

    private func tiltVelocity(_ delta: Double) -> Double {
        let mag = abs(delta)
        guard mag > config.deadzone else { return 0 }
        let norm = min(1, (mag - config.deadzone) / (config.fullScale - config.deadzone))
        // Ease-in curve: gentle near the deadzone, strong at full tilt.
        let v = norm * norm * config.maxTiltVelocity * config.sensitivity
        return delta < 0 ? -v : v
    }

    // MARK: Flick

    private func processFlick(_ s: MotionSample) -> [ProcessorOutput] {
        let fy = pitchFlick.step(rate: s.pitchRate, t: s.t, config: config)
        let fx = rollFlick.step(rate: s.rollRate, t: s.t, config: config)
        guard fx != nil || fy != nil else { return [] }
        let vy = fy.map { signed($0, invert: config.invertY) } ?? 0
        let vx = fx.map { signed($0, invert: config.invertX) } ?? 0
        // The stronger axis wins; a diagonal snap is almost always one dominant motion.
        if abs(vy) >= abs(vx) {
            return [.fling(vx: 0, vy: Int(vy.rounded()))]
        }
        return [.fling(vx: Int(vx.rounded()), vy: 0)]
    }

    private func signed(_ v: Double, invert: Bool) -> Double {
        invert ? -v : v
    }
}

/// Detects one fast, short rotation on a single axis and ignores the
/// return stroke that follows it.
struct AxisFlick {
    private enum State {
        case idle
        case rising(sign: Double, start: TimeInterval, peak: Double, angle: Double, last: TimeInterval)
        case cooldown(until: TimeInterval)
    }

    private var state = State.idle

    mutating func step(rate: Double, t: TimeInterval, config: ProcessorConfig) -> Double? {
        switch state {
        case .cooldown(let until):
            if t >= until { state = .idle }
            return nil

        case .idle:
            if abs(rate) >= config.flickStartRate {
                state = .rising(sign: rate < 0 ? -1 : 1, start: t, peak: abs(rate), angle: 0, last: t)
            }
            return nil

        case let .rising(sign, start, peak, angle, last):
            let dt = max(0, t - last)
            let newAngle = angle + rate * dt
            let newPeak = max(peak, abs(rate) * (rate * sign > 0 ? 1 : 0))
            let ended = abs(rate) < config.flickEndRate || rate * sign < 0
            if t - start > config.flickMaxDuration {
                // Slow, deliberate rotation: not a flick.
                state = .cooldown(until: t + config.flickCooldown)
                return nil
            }
            if ended {
                state = .cooldown(until: t + config.flickCooldown)
                guard abs(newAngle) >= config.flickMinAngle else { return nil }
                let v = min(config.maxFlickVelocity,
                            newPeak * config.flickGain * config.sensitivity)
                return sign * v
            }
            state = .rising(sign: sign, start: start, peak: newPeak, angle: newAngle, last: t)
            return nil
        }
    }
}

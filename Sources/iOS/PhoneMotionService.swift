import CoreMotion
import Foundation
import ScrollCore
import os

/// Turns flicks of the iPhone itself into scroll commands using its gyroscope.
///
/// Axis mapping (phone held upright, screen facing you): tipping the top toward
/// or away from you rotates about the device x-axis and drives vertical
/// scrolling; tilting it left or right rotates about the y-axis and drives
/// horizontal scrolling. Signs differ per person, which is what the phone
/// calibration and the "Reverse" settings are for.
final class PhoneMotionService: @unchecked Sendable {
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "dev.doomscroll.phonemotion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private let log = Logger(subsystem: "dev.doomscroll.ios", category: "phonemotion")
    private let processor = WristMotionProcessor()
    private var needsNeutral = true
    private var calibration: CalibrationSession?

    /// Called on the motion queue with each message to send to the Mac.
    var onOutput: (@Sendable (WireMessage) -> Void)?
    /// Called on the motion queue while calibrating.
    var onCalibration: (@Sendable (CalibrationSession.Outcome) -> Void)?

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start(settings: ScrollSettings) {
        guard motion.isDeviceMotionAvailable else { return }
        processor.config = settings.phoneProcessorConfig
        needsNeutral = true
        calibration = nil
        beginUpdates()
    }

    func startCalibration(_ session: CalibrationSession) {
        guard motion.isDeviceMotionAvailable else { return }
        calibration = session
        beginUpdates()
    }

    func stopCalibration() {
        calibration = nil
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        calibration = nil
    }

    func update(settings: ScrollSettings) {
        queue.addOperation { [processor] in processor.config = settings.phoneProcessorConfig }
    }

    private func beginUpdates() {
        guard !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] dm, error in
            guard let self else { return }
            if let error {
                self.log.error("motion error: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let dm else { return }
            self.handle(dm)
        }
    }

    private func handle(_ dm: CMDeviceMotion) {
        // ScrollCore's "pitch" is the vertical-scroll axis, "roll" the horizontal one.
        let sample = MotionSample(t: dm.timestamp,
                                  pitch: dm.attitude.pitch, roll: dm.attitude.roll,
                                  pitchRate: dm.rotationRate.x, rollRate: dm.rotationRate.y)
        if let calibration {
            let outcome = calibration.process(sample)
            if outcome != .none { onCalibration?(outcome) }
            return
        }
        if needsNeutral {
            processor.begin(neutralPitch: sample.pitch, neutralRoll: sample.roll)
            needsNeutral = false
        }
        for output in processor.process(sample) {
            switch output {
            case let .scroll(dx, dy): onOutput?(.scroll(dx: dx, dy: dy))
            case let .fling(vx, vy): onOutput?(.fling(vx: vx, vy: vy))
            }
        }
    }
}

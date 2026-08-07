import CoreMotion
import Foundation
import os

/// Single owner of `CMMotionManager` on the Watch (Core Motion documents that
/// an app should create only one). Runs device-motion updates at 50 Hz while
/// the app is frontmost: user acceleration feeds double-tap detection,
/// rotation rate feeds gyro scroll samples. Outbound messages are throttled
/// separately to 20 Hz by `WatchSessionManager`.
final class MotionService {
    struct GyroSample {
        /// rad/s around the axis across the wrist — tilting the watch face
        /// toward/away from you. Mapped to vertical scrolling.
        var pitchRate: Double
        /// rad/s around the axis along the forearm — rolling the wrist.
        /// Mapped to horizontal scrolling. Yaw is intentionally ignored.
        var rollRate: Double
        var timestamp: TimeInterval
    }

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "MotionService.updates"
        return q
    }()
    private let log = Logger(subsystem: "dev.lejacob.doomscroll.watchkitapp",
                             category: "motion")

    let tapDetector = DoubleTapDetector()

    /// Rotation below this (rad/s) counts as "not moving" for drift suppression.
    private let zeroVelocityThreshold = 0.1
    /// After this long below the threshold, output is forced to zero so gyro
    /// drift never produces a slow phantom scroll.
    private let zeroVelocityHold: TimeInterval = 0.2
    private var lowMotionSince: TimeInterval?

    /// Called on the motion queue; the consumer is responsible for hopping to
    /// the main actor.
    var onGyroSample: ((GyroSample) -> Void)?
    var gyroStreamingEnabled = false

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard motion.isDeviceMotionAvailable else {
            log.error("Device motion unavailable; cannot detect taps or stream gyro")
            return
        }
        isRunning = true
        motion.deviceMotionUpdateInterval = 0.02
        motion.startDeviceMotionUpdates(to: queue) { [weak self] deviceMotion, error in
            guard let self else { return }
            if let error {
                self.log.error("Device motion error: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let dm = deviceMotion else { return }
            let now = Date().timeIntervalSince1970
            self.tapDetector.process(userAcceleration: dm.userAcceleration, at: now)
            guard self.gyroStreamingEnabled else { return }
            self.onGyroSample?(self.gyroSample(from: dm, at: now))
        }
        log.info("Motion updates started")
    }

    func stop() {
        guard isRunning else { return }
        motion.stopDeviceMotionUpdates()
        isRunning = false
        lowMotionSince = nil
        tapDetector.reset()
        log.info("Motion updates stopped")
    }

    private func gyroSample(from dm: CMDeviceMotion, at now: TimeInterval) -> GyroSample {
        var pitchRate = dm.rotationRate.x
        var rollRate = dm.rotationRate.y

        let magnitude = (pitchRate * pitchRate + rollRate * rollRate).squareRoot()
        if magnitude < zeroVelocityThreshold {
            if let since = lowMotionSince {
                if now - since >= zeroVelocityHold {
                    pitchRate = 0
                    rollRate = 0
                }
            } else {
                lowMotionSince = now
            }
        } else {
            lowMotionSince = nil
        }
        return GyroSample(pitchRate: pitchRate, rollRate: rollRate, timestamp: now)
    }
}

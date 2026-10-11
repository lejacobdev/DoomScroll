import CoreMotion
import Foundation
import ScrollCore
import os

/// Owns the single `CMMotionManager` and feeds wrist motion through
/// `WristMotionProcessor`. Runs on its own queue so scroll latency never
/// depends on the main thread.
///
/// Axis mapping (watch worn normally, forearm along device x): snapping the
/// hand up/down rotates about device **y** and drives vertical scrolling;
/// rolling the forearm rotates about device **x** and drives horizontal
/// scrolling. Left/right wrist and crown placement flip signs, which the
/// "Invert" settings cover.
final class MotionService: @unchecked Sendable {
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "dev.doomscroll.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private let log = Logger(subsystem: "dev.doomscroll.watch", category: "motion")
    private let processor = WristMotionProcessor()
    private var needsNeutral = true
    private var lastSent: TimeInterval = 0

    /// Called on the motion queue with each output to transmit.
    var onOutput: (@Sendable (WireMessage) -> Void)?

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start(settings: ScrollSettings) {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        processor.config = settings.processorConfig
        needsNeutral = true
        lastSent = 0
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
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

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    func update(settings: ScrollSettings) {
        queue.addOperation { [processor] in processor.config = settings.processorConfig }
    }

    private func handle(_ dm: CMDeviceMotion) {
        // ScrollCore's "pitch" is the vertical-scroll axis (device y); "roll" is horizontal (device x).
        let verticalAngle = dm.attitude.roll
        let horizontalAngle = dm.attitude.pitch
        if needsNeutral {
            processor.begin(neutralPitch: verticalAngle, neutralRoll: horizontalAngle)
            needsNeutral = false
        }
        let sample = MotionSample(t: dm.timestamp, pitch: verticalAngle, roll: horizontalAngle,
                                  pitchRate: dm.rotationRate.y, rollRate: dm.rotationRate.x)
        for output in processor.process(sample) {
            switch output {
            case let .scroll(dx, dy): onOutput?(.scroll(dx: dx, dy: dy))
            case let .fling(vx, vy): onOutput?(.fling(vx: vx, vy: vy))
            }
        }
    }
}

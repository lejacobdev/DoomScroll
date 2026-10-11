import Foundation
import HealthKit
import os

/// Keeps the app running (and motion updates flowing) with the wrist down,
/// using a workout session. No workout data is recorded or saved.
///
/// App Review note: this uses HealthKit only to stay alive. For public App
/// Store release, consider the review implications described in docs/RELEASE.md.
final class KeepAliveSession: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private let log = Logger(subsystem: "dev.doomscroll.watch", category: "keepalive")

    func start() async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            let config = HKWorkoutConfiguration()
            config.activityType = .other
            config.locationType = .indoor
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            s.delegate = self
            session = s
            s.startActivity(with: Date())
        } catch {
            log.error("keep-alive failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        session?.end()
        session = nil
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        log.error("workout session error: \(error.localizedDescription, privacy: .public)")
    }
}

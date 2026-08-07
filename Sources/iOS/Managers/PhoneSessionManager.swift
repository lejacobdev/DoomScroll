import Foundation
import WatchConnectivity
import os

/// iPhone-side WatchConnectivity listener. Parses incoming scroll messages,
/// drops stale ones, and forwards the rest to `onCommand` on the main queue.
final class PhoneSessionManager: NSObject, ObservableObject {
    @Published var isWatchReachable = false
    @Published var isWatchAppInstalled = false
    @Published var lastCommandAt: Date?

    /// Delivered on the main queue.
    var onCommand: ((ScrollCommand) -> Void)?

    private let log = Logger(subsystem: "dev.lejacob.doomscroll", category: "connectivity")

    func activate() {
        guard WCSession.isSupported() else {
            log.error("WCSession unsupported (iPad?); Watch control unavailable")
            return
        }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    private func publishState(from session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
}

extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            log.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            log.info("WCSession activated (state \(activationState.rawValue))")
        }
        publishState(from: session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after a watch switch, as Apple's docs recommend.
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        publishState(from: session)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = ScrollCommand(dictionary: message) else {
            log.warning("Dropped unparseable message")
            return
        }
        // Timestamps detect stale data: WatchConnectivity can stall and then
        // flush a burst; replaying old motion feels like the phone scrolling
        // on its own, so anything past the freshness window is dropped.
        guard !command.isStale else {
            log.debug("Dropped stale command (age \(command.age, format: .fixed(precision: 3))s)")
            return
        }
        DispatchQueue.main.async {
            self.lastCommandAt = Date()
            self.onCommand?(command)
        }
    }
}

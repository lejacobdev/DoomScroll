import Foundation
import WatchConnectivity
import os

/// Watch-side WatchConnectivity wrapper. Streams `ScrollCommand`s to the
/// paired iPhone via `sendMessage` (the low-latency interactive channel),
/// throttled to one message per 50 ms.
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isReachable = false
    /// Consecutive send failures; the UI warns the user when this climbs so
    /// silent delivery loss is visible on the wrist.
    @Published var sendFailureStreak = 0

    private let log = Logger(subsystem: "dev.lejacob.doomscroll.watchkitapp",
                             category: "connectivity")
    private let sendInterval: TimeInterval = 0.05
    private var lastSentAt: TimeInterval = 0

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            log.error("WCSession unsupported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Sends a scroll command, dropping it if the last send was under 50 ms
    /// ago. Final `isActive: false` messages bypass the throttle so mode exit
    /// is never lost to rate limiting.
    func send(_ command: ScrollCommand) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            // sendMessage only works while the phone app is reachable; there is
            // no point queueing 20 Hz motion data, so drop silently.
            return
        }
        let now = Date().timeIntervalSince1970
        if command.isActive && now - lastSentAt < sendInterval { return }
        lastSentAt = now

        session.sendMessage(command.dictionary, replyHandler: nil) { [weak self] error in
            guard let self else { return }
            self.log.error("sendMessage failed: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { self.sendFailureStreak += 1 }
        }
    }

    func resetFailureStreak() {
        DispatchQueue.main.async { self.sendFailureStreak = 0 }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            log.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            log.info("WCSession activated (state \(activationState.rawValue))")
        }
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        log.info("Reachability changed: \(session.isReachable)")
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }
}

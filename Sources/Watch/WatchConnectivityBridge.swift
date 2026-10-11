import Foundation
import ScrollCore
import WatchConnectivity
import os

/// Watch side of WatchConnectivity: receives pairing and settings from the
/// iPhone, and relays scroll messages through it when the Mac is not
/// directly reachable.
final class WatchConnectivityBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "dev.doomscroll.watch", category: "wc")
    private let lock = NSLock()
    private var lastContinuousRelay: TimeInterval = 0

    var onPairing: (@Sendable (PairingToken?) -> Void)?
    var onSettings: (@Sendable (ScrollSettings) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Relays through the iPhone. Continuous updates are limited to 25 Hz;
    /// the relay path has more latency and must not flood the queue.
    func relay(_ message: WireMessage) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        if case .scroll = message {
            let now = ProcessInfo.processInfo.systemUptime
            lock.lock()
            let tooSoon = now - lastContinuousRelay < 0.04
            if !tooSoon { lastContinuousRelay = now }
            lock.unlock()
            if tooSoon { return }
        }
        session.sendMessage(WCKey.dictionary(for: message), replyHandler: nil) { [log] error in
            log.debug("relay failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Queued, reliable delivery (survives the iPhone app not running).
    func send(control: ControlMessage) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(control.dictionary)
    }

    var isRelayAvailable: Bool {
        let s = WCSession.default
        return s.activationState == .activated && s.isReachable
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error { log.error("activation: \(error.localizedDescription, privacy: .public)") }
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        if let json = context[WCKey.settings] as? Data,
           let settings = try? JSONDecoder().decode(ScrollSettings.self, from: json) {
            onSettings?(settings)
        }
        if let url = context[WCKey.pairing] as? String {
            onPairing?(url.isEmpty ? nil : PairingToken(urlString: url))
        }
    }
}

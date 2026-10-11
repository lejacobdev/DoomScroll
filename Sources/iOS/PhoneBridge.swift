import Foundation
import ScrollCore
import WatchConnectivity
import os

/// iPhone side of WatchConnectivity: pushes pairing and settings to the
/// Watch, and forwards the Watch's live messages to the Mac.
final class PhoneBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "dev.doomscroll.ios", category: "wc")

    /// Called for every live message from the Watch (on a WatchConnectivity queue).
    var onMessage: (@Sendable (WireMessage) -> Void)?
    var onStatusChange: (@Sendable (_ installed: Bool, _ reachable: Bool) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(settings: ScrollSettings, pairing: PairingToken?) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        guard let json = try? JSONEncoder().encode(settings) else { return }
        do {
            try session.updateApplicationContext([
                WCKey.settings: json,
                WCKey.pairing: pairing?.urlString ?? "",
            ])
        } catch {
            log.error("context push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reportStatus() {
        let s = WCSession.default
        onStatusChange?(s.isWatchAppInstalled, s.isReachable)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        reportStatus()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) { reportStatus() }
    func sessionWatchStateDidChange(_ session: WCSession) { reportStatus() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let m = WCKey.message(from: message) else { return }
        onMessage?(m)
    }
}

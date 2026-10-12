import Foundation
import ScrollCore

/// Chooses the path for each outgoing message. Safe to call from any thread
/// (the motion queue calls it for every sample).
final class Transport: @unchecked Sendable {
    private let lock = NSLock()
    private var link: MacLink?
    private var relayOnly = false
    private let bridge: WatchConnectivityBridge

    init(bridge: WatchConnectivityBridge) {
        self.bridge = bridge
    }

    /// When the destination is this iPhone, never use the Mac link.
    func setRelayOnly(_ on: Bool) {
        lock.lock(); relayOnly = on; lock.unlock()
    }

    func setLink(_ new: MacLink?) {
        lock.lock()
        let old = link
        link = new
        lock.unlock()
        if old !== new { old?.stop() }
    }

    func startLink() {
        lock.lock(); let l = link; lock.unlock()
        l?.start()
    }

    func stopLink() {
        lock.lock(); let l = link; lock.unlock()
        l?.stop()
    }

    /// Direct to the Mac when the Watch can reach it, otherwise relayed via the iPhone.
    func send(_ message: WireMessage) {
        lock.lock(); let l = link; let viaPhone = relayOnly; lock.unlock()
        if !viaPhone, let l, l.isReady {
            l.send(message)
        } else {
            bridge.relay(message)
        }
    }
}

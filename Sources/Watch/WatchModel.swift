import Foundation
import ScrollCore
import SwiftUI
import WatchKit

@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var scrollMode = false
    @Published private(set) var linkState: MacLink.State = .idle
    @Published private(set) var relayAvailable = false
    @Published private(set) var token: PairingToken?
    @Published private(set) var settings = ScrollSettings()
    @Published private(set) var motionUnavailable = false

    private let motion = MotionService()
    private let bridge = WatchConnectivityBridge()
    private let keepAlive = KeepAliveSession()
    private lazy var transport = Transport(bridge: bridge)
    private var relayPoll: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let s = try? JSONDecoder().decode(ScrollSettings.self, from: data) {
            settings = s
        }
        token = PairingToken.loadStored()
        motionUnavailable = !motion.isAvailable

        bridge.onSettings = { [weak self] s in Task { @MainActor in self?.apply(settings: s) } }
        bridge.onPairing = { [weak self] t in Task { @MainActor in self?.apply(token: t) } }
        motion.onOutput = { [transport] message in transport.send(message) }
        bridge.activate()
        rebuildLink()

        relayPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.relayAvailable = self?.bridge.isRelayAvailable ?? false }
        }
    }

    // MARK: Scroll mode

    func toggleScrollMode() {
        setScrollMode(!scrollMode)
    }

    func setScrollMode(_ on: Bool) {
        guard on != scrollMode else { return }
        guard token != nil, !motionUnavailable else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        scrollMode = on
        haptic(on ? .start : .stop)
        if on {
            transport.startLink()
            Task { await keepAlive.start() }
            motion.start(settings: settings)
            transmit(.mode(active: true, target: settings.target))
        } else {
            motion.stop()
            transmit(.scroll(dx: 0, dy: 0))
            transmit(.mode(active: false, target: settings.target))
            keepAlive.stop()
        }
    }

    /// Call when the app leaves the foreground without an active session.
    func appBecameInactive() {
        if !scrollMode { transport.stopLink() }
    }

    func appBecameActive() {
        transport.startLink()
    }

    // MARK: Transport

    private func transmit(_ message: WireMessage) {
        transport.send(message)
    }

    private func rebuildLink() {
        transport.setLink(nil)
        linkState = .idle
        guard let token else { return }
        let l = MacLink(token: token) { [weak self] state in
            Task { @MainActor in self?.linkState = state }
        }
        transport.setLink(l)
        l.start()
    }

    // MARK: Inbound from iPhone

    private func apply(settings new: ScrollSettings) {
        settings = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: "settings") }
        motion.update(settings: new)
    }

    private func apply(token new: PairingToken?) {
        if let new {
            if new == token { return }
            new.store()
        } else {
            PairingToken.clearStored()
        }
        token = new
        rebuildLink()
    }

    private func haptic(_ type: WKHapticType) {
        if settings.hapticsEnabled { WKInterfaceDevice.current().play(type) }
    }
}

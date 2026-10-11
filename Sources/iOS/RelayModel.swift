import Foundation
import ScrollCore
import SwiftUI
import UIKit

@MainActor
final class RelayModel: ObservableObject {
    @Published private(set) var token: PairingToken?
    @Published private(set) var linkState: MacLink.State = .idle
    @Published private(set) var watchInstalled = false
    @Published private(set) var watchReachable = false
    @Published var settings: ScrollSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "settings")
            }
            pushToWatch()
        }
    }
    @Published var scanError: String?

    private let bridge = PhoneBridge()
    private var link: MacLink?
    private var relayedCount = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let s = try? JSONDecoder().decode(ScrollSettings.self, from: data) {
            settings = s
        } else {
            settings = ScrollSettings()
        }
        token = PairingToken.loadStored()

        bridge.onMessage = { [weak self] message in self?.forward(message) }
        bridge.onStatusChange = { [weak self] installed, reachable in
            Task { @MainActor in
                self?.watchInstalled = installed
                self?.watchReachable = reachable
                if installed { self?.pushToWatch() }
            }
        }
        bridge.activate()
        rebuildLink()
    }

    // MARK: Pairing

    func pair(withScanned string: String) {
        guard let new = PairingToken(urlString: string) else {
            scanError = "That QR code isn't a DoomScroll pairing code."
            return
        }
        scanError = nil
        new.store()
        token = new
        rebuildLink()
        pushToWatch()
    }

    func unpair() {
        PairingToken.clearStored()
        token = nil
        link?.stop()
        link = nil
        linkState = .idle
        pushToWatch()
    }

    // MARK: Lifecycle

    func appBecameActive() {
        UIApplication.shared.isIdleTimerDisabled = true
        link?.start()
        pushToWatch()
    }

    func appResignedActive() {
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Relay

    /// Forwards Watch messages to the Mac. Runs off the main actor for latency.
    private nonisolated func forward(_ message: WireMessage) {
        MainActorLinkAccess.shared.link?.send(message)
    }

    private func rebuildLink() {
        link?.stop()
        link = nil
        MainActorLinkAccess.shared.link = nil
        linkState = .idle
        guard let token else { return }
        let l = MacLink(token: token) { [weak self] state in
            Task { @MainActor in self?.linkState = state }
        }
        link = l
        MainActorLinkAccess.shared.link = l
        l.start()
    }

    private func pushToWatch() {
        bridge.push(settings: settings, pairing: token)
    }
}

/// Thread-safe holder so the WatchConnectivity queue can reach the link
/// without hopping to the main actor.
final class MainActorLinkAccess: @unchecked Sendable {
    static let shared = MainActorLinkAccess()
    private let lock = NSLock()
    private var _link: MacLink?
    var link: MacLink? {
        get { lock.lock(); defer { lock.unlock() }; return _link }
        set { lock.lock(); _link = newValue; lock.unlock() }
    }
}

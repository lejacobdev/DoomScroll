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
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }
    @Published var scanError: String?

    private let bridge = PhoneBridge()
    private var link: MacLink?

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let s = try? JSONDecoder().decode(ScrollSettings.self, from: data) {
            settings = s
        } else {
            settings = ScrollSettings()
        }
        hasOnboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")
        token = PairingToken.loadStored()

        bridge.onMessage = { message in
            MainActorLinkAccess.shared.link?.send(message)
            BackgroundKeeper.shared.touch()
        }
        bridge.onControl = { [weak self] control in
            Task { @MainActor in self?.apply(control) }
        }
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

    var isPaired: Bool { token != nil }

    // MARK: Pairing

    /// Returns true when the scanned string was a valid pairing code.
    @discardableResult
    func pair(withScanned string: String) -> Bool {
        guard let new = PairingToken(urlString: string) else {
            scanError = "That isn't a DoomScroll code. Use the one shown by the Mac app."
            Haptics.error()
            return false
        }
        scanError = nil
        new.store()
        token = new
        rebuildLink()
        pushToWatch()
        Haptics.success()
        return true
    }

    func unpair() {
        PairingToken.clearStored()
        token = nil
        link?.stop()
        link = nil
        MainActorLinkAccess.shared.link = nil
        linkState = .idle
        pushToWatch()
    }

    func resetCalibration() {
        settings.calibrated = false
    }

    func finishOnboarding() {
        hasOnboarded = true
    }

    func restartOnboarding() {
        hasOnboarded = false
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

    // MARK: Internals

    private func apply(_ control: ControlMessage) {
        switch control {
        case let .calibrationResult(invertX, invertY):
            var s = settings
            s.invertX = invertX
            s.invertY = invertY
            s.calibrated = true
            settings = s
            Haptics.success()
        }
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

/// Holds a short background-execution assertion while Watch messages are
/// flowing, so relaying continues for a while after the screen locks.
final class BackgroundKeeper: @unchecked Sendable {
    static let shared = BackgroundKeeper()
    private let lock = NSLock()
    private var lastTouch = Date.distantPast
    private var taskID = UIBackgroundTaskIdentifier.invalid

    func touch() {
        lock.lock()
        let now = Date()
        let skip = now.timeIntervalSince(lastTouch) < 1
        if !skip { lastTouch = now }
        lock.unlock()
        guard !skip else { return }
        DispatchQueue.main.async { self.ensureTask() }
    }

    @MainActor
    private func ensureTask() {
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: "relay") { [weak self] in
            self?.endTask()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.endTask() }
    }

    @MainActor
    private func endTask() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }
}

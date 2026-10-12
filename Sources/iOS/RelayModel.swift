import Foundation
import ScrollCore
import SwiftUI
import UIKit

@MainActor
final class RelayModel: ObservableObject {
    enum PhoneCalibrationPhase: Equatable {
        case idle
        case waiting(CalibrationSession.Step)
        case sameMotion(CalibrationSession.Step)
        case accepted(CalibrationSession.Step)
        case done
    }

    @Published private(set) var phoneScrolling = false
    @Published private(set) var phoneCalibration: PhoneCalibrationPhase = .idle
    @Published private(set) var token: PairingToken?
    @Published private(set) var linkState: MacLink.State = .idle
    @Published private(set) var linkViaBluetooth = false
    @Published private(set) var watchInstalled = false
    @Published private(set) var watchReachable = false
    @Published var settings: ScrollSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "settings")
            }
            MainActorLinkAccess.shared.destination = settings.destination
            PhoneScroller.shared.paged = settings.reelsMode
            if oldValue.connection != settings.connection { rebuildLink() }
            phoneMotion.update(settings: settings)
            if phoneScrolling && settings.style != .phone { setPhoneScrolling(false) }
            pushToWatch()
        }
    }
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }
    @Published var scanError: String?

    private let bridge = PhoneBridge()
    private let phoneMotion = PhoneMotionService()
    private var phoneCalibrationSession: CalibrationSession?
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
        MainActorLinkAccess.shared.destination = settings.destination
        PhoneScroller.shared.paged = settings.reelsMode

        bridge.onMessage = { message in
            MainActorLinkAccess.shared.route(message)
            BackgroundKeeper.shared.touch()
        }
        phoneMotion.onOutput = { message in
            MainActorLinkAccess.shared.route(message)
        }
        phoneMotion.onCalibration = { [weak self] outcome in
            Task { @MainActor in self?.handlePhone(outcome) }
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
        // iOS stops delivering motion in the background, so end the session cleanly
        // and make sure the Mac is not left thinking scroll mode is still on.
        setPhoneScrolling(false)
        if phoneCalibration != .idle { cancelPhoneCalibration() }
    }

    // MARK: Phone flick

    var phoneMotionAvailable: Bool { phoneMotion.isAvailable }

    func togglePhoneScrolling() {
        setPhoneScrolling(!phoneScrolling)
    }

    func setPhoneScrolling(_ on: Bool) {
        guard on != phoneScrolling else { return }
        if on {
            let hasDestination = settings.destination == .phone || (isPaired && linkState == .ready)
            guard settings.style == .phone, phoneMotion.isAvailable, hasDestination else {
                Haptics.error()
                return
            }
            phoneScrolling = true
            phoneMotion.start(settings: settings)
            MainActorLinkAccess.shared.route(.mode(active: true, target: settings.target))
            Haptics.success()
        } else {
            phoneScrolling = false
            phoneMotion.stop()
            let access = MainActorLinkAccess.shared
            access.route(.scroll(dx: 0, dy: 0))
            access.route(.mode(active: false, target: settings.target))
            Haptics.tap()
        }
    }

    func startPhoneCalibration() {
        setPhoneScrolling(false)
        let session = CalibrationSession()
        phoneCalibrationSession = session
        phoneCalibration = .waiting(.down)
        phoneMotion.startCalibration(session)
    }

    func cancelPhoneCalibration() {
        phoneMotion.stop()
        phoneCalibrationSession = nil
        phoneCalibration = .idle
    }

    func finishPhoneCalibrationScreen() {
        phoneCalibration = .idle
    }

    private func handlePhone(_ outcome: CalibrationSession.Outcome) {
        switch outcome {
        case .none:
            break
        case let .accepted(step):
            Haptics.success()
            phoneCalibration = .accepted(step)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                if case .accepted = phoneCalibration { phoneCalibration = .waiting(.right) }
            }
        case let .sameMotion(expected):
            Haptics.error()
            phoneCalibration = .sameMotion(expected)
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if case .sameMotion = phoneCalibration { phoneCalibration = .waiting(expected) }
            }
        case let .finished(invertX, invertY, swapAxes):
            phoneMotion.stop()
            phoneCalibrationSession = nil
            var s = settings
            s.phoneInvertX = invertX
            s.phoneInvertY = invertY
            s.phoneSwapAxes = swapAxes
            s.phoneCalibrated = true
            settings = s
            Haptics.success()
            phoneCalibration = .done
        }
    }

    // MARK: Internals

    private func apply(_ control: ControlMessage) {
        switch control {
        case let .calibrationResult(invertX, invertY, swapAxes):
            var s = settings
            s.invertX = invertX
            s.invertY = invertY
            s.swapAxes = swapAxes
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
        let l = MacLink(token: token, onStateChange: { [weak self] state in
            Task { @MainActor in self?.linkState = state }
        }, bluetoothOnly: settings.connection == .bluetooth, onTransportChange: { [weak self] transport in
            Task { @MainActor in self?.linkViaBluetooth = (transport == .bluetooth) }
        })
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
    private var _destination = ScrollDestination.mac
    var link: MacLink? {
        get { lock.lock(); defer { lock.unlock() }; return _link }
        set { lock.lock(); _link = newValue; lock.unlock() }
    }
    var destination: ScrollDestination {
        get { lock.lock(); defer { lock.unlock() }; return _destination }
        set { lock.lock(); _destination = newValue; lock.unlock() }
    }

    /// Sends a message to wherever the user chose: the Mac, or the browser on this iPhone.
    func route(_ message: WireMessage) {
        switch destination {
        case .mac: link?.send(message)
        case .phone: PhoneScrollSink.deliver(message)
        }
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

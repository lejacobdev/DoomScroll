import Foundation
import ScrollCore
import SwiftUI
import WatchKit

@MainActor
final class WatchModel: ObservableObject {
    enum CalibrationPhase: Equatable {
        case idle
        case waiting(CalibrationSession.Step)
        case wrongAxis(CalibrationSession.Step)
        case accepted(CalibrationSession.Step)
        case done
    }

    @Published private(set) var scrollMode = false
    @Published private(set) var linkState: MacLink.State = .idle
    @Published private(set) var relayAvailable = false
    @Published private(set) var token: PairingToken?
    @Published private(set) var settings = ScrollSettings()
    @Published private(set) var motionUnavailable = false
    @Published private(set) var calibration: CalibrationPhase = .idle

    private let motion = MotionService()
    private let bridge = WatchConnectivityBridge()
    private let keepAlive = KeepAliveSession()
    private lazy var transport = Transport(bridge: bridge)
    private var relayPoll: Timer?
    private var calibrationSession: CalibrationSession?

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let s = try? JSONDecoder().decode(ScrollSettings.self, from: data) {
            settings = s
        }
        token = PairingToken.loadStored()
        motionUnavailable = !motion.isAvailable
        transport.setRelayOnly(settings.destination == .phone)

        bridge.onSettings = { [weak self] s in Task { @MainActor in self?.apply(settings: s) } }
        bridge.onPairing = { [weak self] t in Task { @MainActor in self?.apply(token: t) } }
        motion.onOutput = { [transport] message in transport.send(message) }
        motion.onCalibration = { [weak self] outcome in Task { @MainActor in self?.handle(outcome) } }
        bridge.activate()
        rebuildLink()

        relayPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.relayAvailable = self?.bridge.isRelayAvailable ?? false }
        }
    }

    /// True once there is somewhere to send scrolls: a paired Mac, or this iPhone's browser.
    var hasDestination: Bool { token != nil || settings.destination == .phone }

    var needsCalibration: Bool { hasDestination && !settings.calibrated }

    // MARK: Scroll mode

    func toggleScrollMode() {
        setScrollMode(!scrollMode)
    }

    func setScrollMode(_ on: Bool) {
        guard on != scrollMode else { return }
        guard hasDestination, !motionUnavailable, calibration == .idle,
              !(on && settings.style == .phone) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        scrollMode = on
        haptic(on ? .start : .stop)
        if on {
            transport.startLink()
            Task { await keepAlive.start() }
            motion.start(settings: settings)
            transport.send(.mode(active: true, target: settings.target))
        } else {
            motion.stop()
            transport.send(.scroll(dx: 0, dy: 0))
            transport.send(.mode(active: false, target: settings.target))
            keepAlive.stop()
        }
    }

    func appBecameInactive() {
        if !scrollMode { transport.stopLink() }
    }

    func appBecameActive() {
        transport.startLink()
    }

    // MARK: Calibration

    func startCalibration() {
        if scrollMode { setScrollMode(false) }
        let session = CalibrationSession()
        calibrationSession = session
        calibration = .waiting(.down)
        motion.startCalibration(session)
    }

    func cancelCalibration() {
        motion.stopCalibration()
        motion.stop()
        calibrationSession = nil
        calibration = .idle
    }

    func finishCalibrationScreen() {
        calibration = .idle
    }

    private func handle(_ outcome: CalibrationSession.Outcome) {
        switch outcome {
        case .none:
            break
        case let .accepted(step):
            WKInterfaceDevice.current().play(.success)
            calibration = .accepted(step)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                if case .accepted = calibration { calibration = .waiting(.right) }
            }
        case let .wrongAxis(expected):
            WKInterfaceDevice.current().play(.failure)
            calibration = .wrongAxis(expected)
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if case .wrongAxis = calibration { calibration = .waiting(expected) }
            }
        case let .finished(invertX, invertY):
            motion.stop()
            calibrationSession = nil
            var updated = settings
            updated.invertX = invertX
            updated.invertY = invertY
            updated.calibrated = true
            apply(settings: updated)
            bridge.send(control: .calibrationResult(invertX: invertX, invertY: invertY))
            WKInterfaceDevice.current().play(.success)
            calibration = .done
        }
    }

    // MARK: Inbound from iPhone

    private func apply(settings new: ScrollSettings) {
        settings = new
        transport.setRelayOnly(new.destination == .phone)
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

    private func haptic(_ type: WKHapticType) {
        if settings.hapticsEnabled { WKInterfaceDevice.current().play(type) }
    }
}

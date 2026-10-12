import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import ScrollCore
import ServiceManagement

@MainActor
final class MacModel: ObservableObject {
    @Published var trusted = ScrollInjector.isTrusted
    @Published var clientCount = 0 {
        didSet { if clientCount > 0 && !hasPairedDevice { hasPairedDevice = true } }
    }
    private var networkClients = 0 { didSet { clientCount = networkClients + bluetoothClients } }
    private var bluetoothClients = 0 { didSet { clientCount = networkClients + bluetoothClients } }
    @Published var hasPairedDevice = UserDefaults.standard.bool(forKey: "hasPairedDevice") {
        didSet { UserDefaults.standard.set(hasPairedDevice, forKey: "hasPairedDevice") }
    }
    @Published var scrollModeActive = false
    @Published var target: ScrollTarget {
        didSet {
            UserDefaults.standard.set(target.rawValue, forKey: "target")
            engine.setTarget(target)
        }
    }
    @Published var paused = false {
        didSet { if paused { engine.stopAll() } }
    }
    @Published var listenerState = "starting"
    @Published private(set) var token: PairingToken
    @Published var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    private let engine = ScrollEngine()
    private var server: ScrollServer?
    private var bluetoothServer: BLEScrollServer?
    private var trustPoll: Timer?
    private var activeTarget: ScrollTarget

    init() {
        let name = Host.current().localizedName ?? "Mac"
        let savedTarget = ScrollTarget(rawValue: UserDefaults.standard.integer(forKey: "target")) ?? .pointer
        target = savedTarget
        activeTarget = savedTarget
        if let stored = PairingToken.loadStored() {
            token = PairingToken(key: stored.key, macName: name)
        } else {
            let fresh = PairingToken.generate(macName: name)
            fresh.store()
            token = fresh
        }
        engine.setTarget(savedTarget)
        startServer()
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trusted = ScrollInjector.isTrusted }
        }
    }

    private func startServer() {
        let callbacks = ScrollServer.Callbacks(
            onMessage: { [weak self] m in Task { @MainActor in self?.handle(m) } },
            onClientCountChanged: { [weak self] n in Task { @MainActor in self?.networkClients = n } },
            onListenerState: { [weak self] s in Task { @MainActor in self?.listenerState = s } })
        let s = ScrollServer(key: token.key, serviceName: token.macName, callbacks: callbacks)
        server = s
        s.start()

        // Bluetooth LE backup: same signed messages, used when Wi-Fi isn't available.
        let bleCallbacks = ScrollServer.Callbacks(
            onMessage: { [weak self] m in Task { @MainActor in self?.handle(m) } },
            onClientCountChanged: { [weak self] n in Task { @MainActor in self?.bluetoothClients = n } },
            onListenerState: { _ in })
        let b = BLEScrollServer(key: token.key, macName: token.macName, callbacks: bleCallbacks)
        bluetoothServer = b
        b.start()
    }

    private func handle(_ message: WireMessage) {
        guard !paused else { return }
        switch message {
        case let .mode(active, requestedTarget):
            scrollModeActive = active
            if active {
                // The Watch can ask for a target; the Mac menu setting is the default.
                engine.setTarget(requestedTarget == .pointer ? target : requestedTarget)
            } else {
                engine.releaseContinuous()
            }
        case let .scroll(dx, dy):
            engine.continuous(dx: dx, dy: dy)
        case let .fling(vx, vy):
            engine.fling(vx: vx, vy: vy)
        case .ping:
            break
        }
    }

    func requestAccessibility() {
        ScrollInjector.requestTrust()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func resetPairing() {
        let fresh = PairingToken.generate(macName: token.macName)
        fresh.store()
        token = fresh
        server?.updateKey(fresh.key)
        bluetoothServer?.updateKey(fresh.key)
        hasPairedDevice = false
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func qrImage() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(token.urlString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

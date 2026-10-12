#if canImport(Network)
import Foundation
import Network
import os

/// Client side of the Mac connection: finds the paired Mac over Bonjour,
/// connects, reconnects with backoff and seals every message.
public final class MacLink: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case searching
        case connecting
        case ready
        /// The system is blocking local-network access (Settings > Privacy > Local Network).
        case localNetworkDenied
    }

    /// Which path is carrying messages while `State.ready`.
    public enum Transport: Equatable, Sendable { case network, bluetooth }

    public static let serviceType = "_doomscroll._tcp"

    private let queue = DispatchQueue(label: "dev.doomscroll.maclink", qos: .userInteractive)
    private let log = Logger(subsystem: "dev.doomscroll", category: "maclink")
    private let token: PairingToken
    private let authenticator: MessageAuthenticator
    private let onStateChange: @Sendable (State) -> Void
    private let onTransportChange: (@Sendable (Transport) -> Void)?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var seq: UInt64 = 0
    private var backoff: TimeInterval = 0.5
    private var wanted = false
    /// State of the Wi-Fi/TCP path only. The public state also accounts for Bluetooth.
    private var state = State.idle { didSet { if state != oldValue { publish(); evaluateFallback() } } }
    private var published = State.idle
    private var publishedTransport = Transport.network
    private var bleReady = false {
        didSet {
            guard bleReady != oldValue else { return }
            publish()
            #if canImport(CoreBluetooth)
            if bleReady, let m = lastMode { sendOverBluetooth(m) }
            #endif
        }
    }
    private var lastMode: WireMessage?
    private var fallbackScheduled = false
    #if canImport(CoreBluetooth)
    private var ble: BLEScrollClient?
    #endif

    public init(token: PairingToken,
                onStateChange: @escaping @Sendable (State) -> Void,
                onTransportChange: (@Sendable (Transport) -> Void)? = nil) {
        self.token = token
        self.authenticator = MessageAuthenticator(key: token.key)
        self.onStateChange = onStateChange
        self.onTransportChange = onTransportChange
        #if canImport(CoreBluetooth)
        self.ble = BLEScrollClient(macName: token.macName) { [weak self] st in
            self?.queue.async { self?.bleReady = (st == .ready) }
        }
        #endif
    }

    public var isReady: Bool {
        queue.sync { published == .ready }
    }

    /// Strictly increasing across reconnects and transports, so the Mac's replay
    /// protection never rejects a fresh connection.
    private func nextSeq() -> UInt64 {
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        seq = max(seq + 1, nowMs)
        return seq
    }

    private func publish() {
        let new: State = (state == .ready || bleReady) ? .ready : state
        if new != published { published = new; onStateChange(new) }
        let transport: Transport = (state != .ready && bleReady) ? .bluetooth : .network
        if transport != publishedTransport { publishedTransport = transport; onTransportChange?(transport) }
    }

    /// Bluetooth only runs while the network path is down, and starts after a short grace
    /// period so a normal Wi-Fi connection never wakes the radio.
    private func evaluateFallback() {
        #if canImport(CoreBluetooth)
        guard wanted else { return }
        if state == .ready {
            ble?.stop()
            fallbackScheduled = false
            return
        }
        guard !fallbackScheduled else { return }
        fallbackScheduled = true
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.fallbackScheduled = false
            if self.wanted, self.state != .ready { self.ble?.start() }
        }
        #endif
    }

    #if canImport(CoreBluetooth)
    private func sendOverBluetooth(_ message: WireMessage) {
        let env = authenticator.seal(message, seq: nextSeq(), nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        if let data = try? LineFramer.encode(env) { ble?.send(data) }
    }
    #endif

    public func start() {
        queue.async {
            guard !self.wanted else { return }
            self.wanted = true
            self.backoff = 0.5
            self.search()
            self.evaluateFallback()
        }
    }

    public func stop() {
        queue.async {
            self.wanted = false
            self.browser?.cancel(); self.browser = nil
            self.connection?.cancel(); self.connection = nil
            #if canImport(CoreBluetooth)
            self.ble?.stop()
            #endif
            self.state = .idle
        }
    }

    /// Sends one message. Continuous scroll updates are dropped while
    /// disconnected; the most recent mode change is replayed on reconnect so
    /// the Mac never gets stuck in scroll mode.
    public func send(_ message: WireMessage) {
        queue.async {
            if case .mode = message { self.lastMode = message }
            if self.state == .ready, let conn = self.connection {
                self.write(message, on: conn)
            } else if self.bleReady {
                #if canImport(CoreBluetooth)
                self.sendOverBluetooth(message)
                #endif
            }
        }
    }

    private func write(_ message: WireMessage, on conn: NWConnection) {
        let env = authenticator.seal(message, seq: nextSeq(), nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        guard let data = try? LineFramer.encode(env) else { return }
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.log.debug("send failed: \(error.localizedDescription, privacy: .public)") }
        })
    }

    // MARK: Discovery

    private func search() {
        guard wanted, browser == nil else { return }
        state = .searching
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            self?.queue.async { self?.handle(results) }
        }
        b.stateUpdateHandler = { [weak self] st in
            self?.queue.async {
                guard let self else { return }
                switch st {
                case .failed:
                    self.restartSearch()
                case let .waiting(error):
                    // -65570 is kDNSServiceErr_PolicyDenied: the user declined Local Network access.
                    if case let .dns(code) = error, code == -65570 {
                        self.state = .localNetworkDenied
                    }
                case .ready:
                    if self.state == .localNetworkDenied { self.state = .searching }
                default: break
                }
            }
        }
        browser = b
        b.start(queue: queue)
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        guard wanted, connection == nil else { return }
        let match = results.first { r in
            if case let .service(name, _, _, _) = r.endpoint { return name == token.macName }
            return false
        }
        guard let match else { return }
        connect(to: match.endpoint)
    }

    private func restartSearch() {
        browser?.cancel(); browser = nil
        schedule { self.search() }
    }

    // MARK: Connection

    private func connect(to endpoint: NWEndpoint) {
        state = .connecting
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        let conn = NWConnection(to: endpoint, using: NWParameters(tls: nil, tcp: tcp))
        connection = conn
        conn.stateUpdateHandler = { [weak self, weak conn] st in
            guard let self, let conn else { return }
            self.queue.async {
                guard self.connection === conn else { return }
                switch st {
                case .ready:
                    self.backoff = 0.5
                    self.state = .ready
                    self.listenForClose(conn)
                    if let m = self.lastMode { self.write(m, on: conn) }
                case .failed, .cancelled:
                    self.dropConnection()
                case .waiting:
                    self.log.debug("connection waiting")
                default: break
                }
            }
        }
        conn.start(queue: queue)
    }

    /// The server never sends data; reading only serves to notice a closed link.
    private func listenForClose(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.queue.async { if self.connection === conn { self.dropConnection() } }
            } else {
                self.listenForClose(conn)
            }
        }
    }

    private func dropConnection() {
        connection?.cancel()
        connection = nil
        guard wanted else { state = .idle; return }
        state = .searching
        schedule { self.handleAfterDrop() }
    }

    private func handleAfterDrop() {
        guard wanted, connection == nil else { return }
        if let b = browser {
            // Re-evaluate current results; the stored set may still contain the Mac.
            b.cancel(); browser = nil
        }
        search()
    }

    private func schedule(_ work: @escaping () -> Void) {
        let delay = backoff
        backoff = min(5, backoff * 2)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.wanted == true else { return }
            work()
        }
    }
}
#endif

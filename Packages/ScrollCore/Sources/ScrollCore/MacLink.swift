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
    }

    public static let serviceType = "_doomscroll._tcp"

    private let queue = DispatchQueue(label: "dev.doomscroll.maclink", qos: .userInteractive)
    private let log = Logger(subsystem: "dev.doomscroll", category: "maclink")
    private let token: PairingToken
    private let authenticator: MessageAuthenticator
    private let onStateChange: @Sendable (State) -> Void

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var seq: UInt64 = 0
    private var backoff: TimeInterval = 0.5
    private var wanted = false
    private var state = State.idle { didSet { if state != oldValue { onStateChange(state) } } }
    private var lastMode: WireMessage?

    public init(token: PairingToken, onStateChange: @escaping @Sendable (State) -> Void) {
        self.token = token
        self.authenticator = MessageAuthenticator(key: token.key)
        self.onStateChange = onStateChange
    }

    public var isReady: Bool {
        queue.sync { state == .ready }
    }

    public func start() {
        queue.async {
            guard !self.wanted else { return }
            self.wanted = true
            self.backoff = 0.5
            self.search()
        }
    }

    public func stop() {
        queue.async {
            self.wanted = false
            self.browser?.cancel(); self.browser = nil
            self.connection?.cancel(); self.connection = nil
            self.state = .idle
        }
    }

    /// Sends one message. Continuous scroll updates are dropped while
    /// disconnected; the most recent mode change is replayed on reconnect so
    /// the Mac never gets stuck in scroll mode.
    public func send(_ message: WireMessage) {
        queue.async {
            if case .mode = message { self.lastMode = message }
            guard self.state == .ready, let conn = self.connection else { return }
            self.write(message, on: conn)
        }
    }

    private func write(_ message: WireMessage, on conn: NWConnection) {
        seq += 1
        let env = authenticator.seal(message, seq: seq, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
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
            if case .failed = st { self?.queue.async { self?.restartSearch() } }
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
                    self.seq = 0
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

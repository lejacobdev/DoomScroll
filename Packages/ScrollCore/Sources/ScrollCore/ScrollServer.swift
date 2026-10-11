#if canImport(Network)
import Foundation
import Network
import os

/// Bonjour-advertised TCP server speaking newline-delimited JSON. Every message is HMAC-authenticated
/// with the pairing key, so unpaired devices on the same network are ignored.
public final class ScrollServer: @unchecked Sendable {
    public struct Callbacks {
        public var onMessage: (WireMessage) -> Void
        public var onClientCountChanged: (Int) -> Void
        public var onListenerState: (String) -> Void

        public init(onMessage: @escaping (WireMessage) -> Void,
                    onClientCountChanged: @escaping (Int) -> Void,
                    onListenerState: @escaping (String) -> Void) {
            self.onMessage = onMessage
            self.onClientCountChanged = onClientCountChanged
            self.onListenerState = onListenerState
        }
    }

    public static let serviceType = "_doomscroll._tcp"

    private let log = Logger(subsystem: "dev.doomscroll.mac", category: "server")
    private let queue = DispatchQueue(label: "dev.doomscroll.server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var authenticator: MessageAuthenticator
    private let serviceName: String
    private let advertise: Bool
    private let callbacks: Callbacks

    /// `advertise: false` skips Bonjour (used by tests).
    public init(key: Data, serviceName: String, advertise: Bool = true, callbacks: Callbacks) {
        self.advertise = advertise
        self.authenticator = MessageAuthenticator(key: key)
        self.serviceName = serviceName
        self.callbacks = callbacks
    }

    public func updateKey(_ key: Data) {
        queue.async {
            self.authenticator = MessageAuthenticator(key: key)
            for c in self.clients.values { c.cancel() }
        }
    }

    /// Bound TCP port once listening (used by tests and diagnostics).
    public var port: UInt16? {
        queue.sync { listener?.port?.rawValue }
    }

    public func start() {
        queue.async {
            guard self.listener == nil else { return }
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            tcp.enableKeepalive = true
            let params = NWParameters(tls: nil, tcp: tcp)
            do {
                let l = try NWListener(using: params)
                if self.advertise {
                    l.service = NWListener.Service(name: self.serviceName, type: Self.serviceType)
                }
                l.stateUpdateHandler = { [weak self] state in
                    self?.callbacks.onListenerState("\(state)")
                    if case .failed = state { self?.restart() }
                }
                l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
                l.start(queue: self.queue)
                self.listener = l
            } catch {
                self.log.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                self.callbacks.onListenerState("failed: \(error.localizedDescription)")
            }
        }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for c in self.clients.values { c.cancel() }
            self.clients.removeAll()
            self.callbacks.onClientCountChanged(0)
        }
    }

    private func restart() {
        queue.asyncAfter(deadline: .now() + 2) {
            self.listener?.cancel()
            self.listener = nil
            self.start()
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        clients[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                self.clients[id] = nil
                self.callbacks.onClientCountChanged(self.clients.count)
            case .ready:
                self.callbacks.onClientCountChanged(self.clients.count)
            default: break
            }
        }
        conn.start(queue: queue)
        receive(on: conn, replay: ReplayGuard())
    }

    private func receive(on conn: NWConnection, replay: ReplayGuard, framer: LineFramer = LineFramer()) {
        var replay = replay
        var framer = framer
        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil || isComplete { conn.cancel(); return }
            if let data {
                do {
                    for line in try framer.push(data) {
                        do {
                            let env = try JSONDecoder().decode(Envelope.self, from: line)
                            let message = try self.authenticator.open(env)
                            try replay.check(env, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
                            self.callbacks.onMessage(message)
                        } catch {
                            self.log.debug("Dropped message: \(String(describing: error), privacy: .public)")
                        }
                    }
                } catch {
                    self.log.error("Closing connection: \(String(describing: error), privacy: .public)")
                    conn.cancel()
                    return
                }
            }
            self.receive(on: conn, replay: replay, framer: framer)
        }
    }
}
#endif

import CryptoKit
import Foundation

public enum ScrollTarget: Int, Codable, Sendable, CaseIterable {
    /// Scroll whatever is under the Mac pointer.
    case pointer = 0
    /// Scroll the iPhone Mirroring window (and so the iPhone).
    case iPhoneMirroring = 1
}

/// Logical message passed Watch -> iPhone -> Mac.
public enum WireMessage: Equatable, Sendable {
    /// Continuous scroll velocity in points per second.
    case scroll(dx: Int, dy: Int)
    /// One-shot impulse in points per second; the receiver applies momentum.
    case fling(vx: Int, vy: Int)
    /// One-shot scroll distance in points, applied right away (Digital Crown).
    case nudge(dx: Int, dy: Int)
    case mode(active: Bool, target: ScrollTarget)
    case ping

    var type: String {
        switch self {
        case .scroll: "scroll"
        case .fling: "fling"
        case .nudge: "nudge"
        case .mode: "mode"
        case .ping: "ping"
        }
    }

    var fields: (Int, Int) {
        switch self {
        case let .scroll(dx, dy): (dx, dy)
        case let .fling(vx, vy): (vx, vy)
        case let .nudge(dx, dy): (dx, dy)
        case let .mode(active, target): (active ? 1 : 0, target.rawValue)
        case .ping: (0, 0)
        }
    }
}

/// Flat, integer-only JSON envelope. Integers keep the MAC input byte-exact
/// across JSON round trips (no floating-point formatting differences).
public struct Envelope: Codable, Equatable, Sendable {
    public static let version = 1

    public var v: Int
    public var seq: UInt64
    public var tsMs: Int64
    public var type: String
    public var a: Int
    public var b: Int
    public var mac: String

    var canonical: Data {
        Data("\(v)|\(seq)|\(tsMs)|\(type)|\(a)|\(b)".utf8)
    }
}

public enum WireError: Error, Equatable {
    case badVersion
    case badMAC
    case unknownType
    case replayed
    case stale
}

public struct MessageAuthenticator: Sendable {
    private let key: SymmetricKey

    public init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    public func seal(_ message: WireMessage, seq: UInt64, nowMs: Int64) -> Envelope {
        let (a, b) = message.fields
        var env = Envelope(v: Envelope.version, seq: seq, tsMs: nowMs,
                           type: message.type, a: a, b: b, mac: "")
        env.mac = Self.hex(Data(HMAC<SHA256>.authenticationCode(for: env.canonical, using: key)))
        return env
    }

    public func open(_ env: Envelope) throws -> WireMessage {
        guard env.v == Envelope.version else { throw WireError.badVersion }
        guard let tag = Self.unhex(env.mac),
              HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: env.canonical, using: key)
        else { throw WireError.badMAC }
        switch env.type {
        case "scroll": return .scroll(dx: env.a, dy: env.b)
        case "fling": return .fling(vx: env.a, vy: env.b)
        case "nudge": return .nudge(dx: env.a, dy: env.b)
        case "mode":
            guard let target = ScrollTarget(rawValue: env.b) else { throw WireError.unknownType }
            return .mode(active: env.a != 0, target: target)
        case "ping": return .ping
        default: throw WireError.unknownType
        }
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func unhex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data(capacity: s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}

/// Rejects replayed and stale envelopes for one connection.
public struct ReplayGuard: Sendable {
    public var maxSkewMs: Int64
    private var lastSeq: UInt64 = 0

    public init(maxSkewMs: Int64 = 30_000) {
        self.maxSkewMs = maxSkewMs
    }

    public mutating func check(_ env: Envelope, nowMs: Int64) throws {
        guard abs(nowMs - env.tsMs) <= maxSkewMs else { throw WireError.stale }
        guard env.seq > lastSeq else { throw WireError.replayed }
        lastSeq = env.seq
    }
}

/// Pairing secret shown as a QR code on the Mac and scanned by the iPhone.
public struct PairingToken: Equatable, Sendable {
    public var key: Data
    public var macName: String

    public init(key: Data, macName: String) {
        self.key = key
        self.macName = macName
    }

    public static func generate(macName: String) -> PairingToken {
        PairingToken(key: Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }),
                     macName: macName)
    }

    public var urlString: String {
        var c = URLComponents()
        c.scheme = "doomscroll"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "k", value: Self.base64url(key)),
            URLQueryItem(name: "n", value: macName),
        ]
        return c.string ?? ""
    }

    public init?(urlString: String) {
        guard let c = URLComponents(string: urlString),
              c.scheme == "doomscroll", c.host == "pair",
              let k = c.queryItems?.first(where: { $0.name == "k" })?.value,
              let key = Self.fromBase64url(k), key.count == 32
        else { return nil }
        self.key = key
        self.macName = c.queryItems?.first(where: { $0.name == "n" })?.value ?? "Mac"
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

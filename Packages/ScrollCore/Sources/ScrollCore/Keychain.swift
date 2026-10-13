import Foundation
import Security

/// Minimal generic-password Keychain wrapper shared by all three apps.
///
/// On macOS the login keychain ties each item to the exact app that created it, so a
/// differently signed build of the same app (a local build vs. TestFlight, for example)
/// can neither read nor replace it, and the Mac silently made a new pairing key on every
/// launch. The data protection keychain (the same one iOS uses) does not have that
/// problem, so the Mac uses it whenever the build has an application identifier
/// (App Store and TestFlight builds). Developer ID builds without one fall back to the
/// login keychain.
public enum Keychain {
    private static func query(service: String, account: String, dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return q
    }

    /// Runs `body` against the data protection keychain, and against the login keychain
    /// only if this build isn't allowed to use the former.
    private static func withKeychain(_ body: (_ dataProtection: Bool) -> OSStatus) -> OSStatus {
        #if os(macOS)
        let status = body(true)
        return status == errSecMissingEntitlement ? body(false) : status
        #else
        return body(true)
        #endif
    }

    public static func load(service: String, account: String) -> Data? {
        var out: CFTypeRef?
        let status = withKeychain { dp in
            var q = query(service: service, account: account, dataProtection: dp)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(q as CFDictionary, &out)
        }
        return status == errSecSuccess ? out as? Data : nil
    }

    @discardableResult
    public static func save(_ data: Data, service: String, account: String) -> Bool {
        let status = withKeychain { dp in
            let q = query(service: service, account: account, dataProtection: dp)
            let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard update == errSecItemNotFound else { return update }
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    public static func delete(service: String, account: String) {
        _ = withKeychain { dp in
            SecItemDelete(query(service: service, account: account, dataProtection: dp) as CFDictionary)
        }
    }
}

extension PairingToken {
    private static let service = "dev.doomscroll.pairing"

    /// Persists the token's key and Mac name.
    @discardableResult
    public func store() -> Bool {
        let blob = (try? JSONEncoder().encode(["k": key.base64EncodedString(), "n": macName])) ?? Data()
        return Keychain.save(blob, service: Self.service, account: "token")
    }

    public static func loadStored() -> PairingToken? {
        guard let blob = Keychain.load(service: service, account: "token"),
              let d = try? JSONDecoder().decode([String: String].self, from: blob),
              let k = d["k"], let key = Data(base64Encoded: k), key.count == 32
        else { return nil }
        return PairingToken(key: key, macName: d["n"] ?? "Mac")
    }

    public static func clearStored() {
        Keychain.delete(service: service, account: "token")
    }
}

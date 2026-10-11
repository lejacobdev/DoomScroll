import Foundation
import Security

/// Minimal generic-password Keychain wrapper shared by all three apps.
public enum Keychain {
    public static func load(service: String, account: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    public static func save(_ data: Data, service: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public static func delete(service: String, account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
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

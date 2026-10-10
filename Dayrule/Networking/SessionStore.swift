import Foundation
import Security

/// Session token + cached unlock material in the Keychain (M2).
struct SessionStore: Sendable {
    private let service = "app.dayrule.session"

    struct CachedAccount: Codable, Sendable {
        var userId: String
        var email: String
        var saltB64: String
        var kdf: KdfDTO
        var wrappedPassword: WrappedB64
        var deviceWrappedAK: WrappedB64?
        /// AK wrapped under the biometric Keychain key (PLAN §8.3).
        var biometricWrappedAK: WrappedB64?
    }

    func saveToken(_ token: String) throws {
        try save(account: "token", data: Data(token.utf8))
    }

    func loadToken() throws -> String? {
        guard let data = try load(account: "token") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() throws {
        try delete(account: "token")
    }

    func saveAccount(_ account: CachedAccount) throws {
        let data = try JSONEncoder().encode(account)
        try save(account: "cached", data: data)
    }

    func loadAccount() throws -> CachedAccount? {
        guard let data = try load(account: "cached") else { return nil }
        return try JSONDecoder().decode(CachedAccount.self, from: data)
    }

    func clear() throws {
        try delete(account: "token")
        try delete(account: "cached")
    }

    private func save(account: String, data: Data) throws {
        if MemoryKeychain.enabled {
            MemoryKeychain.save(service: service, account: account, data: data)
            return
        }
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CryptoError.keychain("save \(status)") }
    }

    private func load(account: String) throws -> Data? {
        if MemoryKeychain.enabled {
            return MemoryKeychain.load(service: service, account: account)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CryptoError.keychain("read \(status)")
        }
        return data
    }

    private func delete(account: String) throws {
        if MemoryKeychain.enabled {
            MemoryKeychain.delete(service: service, account: account)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CryptoError.keychain("delete \(status)")
        }
    }
}

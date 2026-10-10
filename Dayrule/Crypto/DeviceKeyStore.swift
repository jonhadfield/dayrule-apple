import Foundation
import Security

/// Random 256-bit device wrap key in the Keychain (PLAN §8.2). No Secure Enclave.
struct DeviceKeyStore: Sendable {
    private let service = "app.dayrule.device-wrap"

    func loadOrCreate(userId: String) throws -> [UInt8] {
        if let existing = try load(userId: userId) {
            return existing
        }
        let key = Primitives.randomBytes(CryptoConstants.keyBytes)
        try save(userId: userId, key: key)
        return key
    }

    func load(userId: String) throws -> [UInt8]? {
        if MemoryKeychain.enabled {
            return MemoryKeychain.load(service: service, account: userId).map { [UInt8]($0) }
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CryptoError.keychain("read \(status)")
        }
        return [UInt8](data)
    }

    func save(userId: String, key: [UInt8]) throws {
        if MemoryKeychain.enabled {
            MemoryKeychain.save(service: service, account: userId, data: Data(key))
            return
        }
        try delete(userId: userId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId,
            kSecValueData as String: Data(key),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CryptoError.keychain("save \(status)")
        }
    }

    func delete(userId: String) throws {
        if MemoryKeychain.enabled {
            MemoryKeychain.delete(service: service, account: userId)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CryptoError.keychain("delete \(status)")
        }
    }
}

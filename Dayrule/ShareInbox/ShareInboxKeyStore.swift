import Foundation
import Security

/// 256-bit symmetric key for the share queue only (never the account key).
enum ShareInboxKeyStore {
    static func loadOrCreate() throws -> [UInt8] {
        if let override = ShareInboxSupport.keyOverride {
            guard override.count == 32 else { throw ShareInboxError.crypto }
            return override
        }
        if let existing = try load() { return existing }
        var key = [UInt8](repeating: 0, count: 32)
        let status = key.withUnsafeMutableBytes { buf in
            SecRandomCopyBytes(kSecRandomDefault, 32, buf.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw ShareInboxError.keychain(status)
        }
        try save(key)
        return key
    }

    static func load() throws -> [UInt8]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ShareInboxSupport.keychainService,
            kSecAttrAccessGroup as String: ShareInboxSupport.keychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ShareInboxError.keychain(status)
        }
        return Array(data)
    }

    private static func save(_ key: [UInt8]) throws {
        let data = Data(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ShareInboxSupport.keychainService,
            kSecAttrAccessGroup as String: ShareInboxSupport.keychainAccessGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: ShareInboxSupport.keychainService,
                    kSecAttrAccessGroup as String: ShareInboxSupport.keychainAccessGroup,
                ] as CFDictionary,
                update as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ShareInboxError.keychain(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw ShareInboxError.keychain(status)
        }
    }
}

enum ShareInboxError: Error, Equatable, LocalizedError {
    case keychain(OSStatus)
    case crypto
    case containerMissing
    case corruptQueue

    var errorDescription: String? {
        switch self {
        case .keychain(let s): return "Share inbox Keychain error (\(s))"
        case .crypto: return "Share inbox encryption failed"
        case .containerMissing: return "Share inbox App Group container missing"
        case .corruptQueue: return "Share inbox queue is corrupt"
        }
    }
}

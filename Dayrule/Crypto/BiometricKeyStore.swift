import Foundation
import LocalAuthentication
import Security

/// Biometric-gated wrap key (PLAN §8.3). The gate is the Keychain read —
/// never a standalone `LAContext.evaluatePolicy` boolean.
struct BiometricKeyStore: Sendable {
    private let service = "uk.co.lessknown.dayrule.biometric-wrap"

    /// True when the device can use biometrics (UI only; unlock still goes
    /// through Keychain).
    func biometryAvailable() -> Bool {
        if MemoryKeychain.enabled { return true }
        let ctx = LAContext()
        var error: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func biometryName() -> String {
        if MemoryKeychain.enabled { return "Biometrics" }
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometrics"
        }
    }

    func loadOrCreate(userId: String) throws -> [UInt8] {
        if let existing = try load(userId: userId) {
            return existing
        }
        let key = Primitives.randomBytes(CryptoConstants.keyBytes)
        try save(userId: userId, key: key)
        return key
    }

    /// Reading this item prompts for biometrics via Keychain access control.
    func load(userId: String) throws -> [UInt8]? {
        if MemoryKeychain.enabled {
            return MemoryKeychain.load(service: service, account: userId).map { [UInt8]($0) }
        }
        let ctx = LAContext()
        ctx.localizedReason = "Unlock Dayrule"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: ctx,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || status == errSecUserCanceled {
            return nil
        }
        if status == errSecAuthFailed {
            throw CryptoError.keychain("biometry denied")
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CryptoError.keychain("biometric read \(status)")
        }
        return [UInt8](data)
    }

    func save(userId: String, key: [UInt8]) throws {
        if MemoryKeychain.enabled {
            MemoryKeychain.save(service: service, account: userId, data: Data(key))
            return
        }
        try delete(userId: userId)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw CryptoError.keychain("access control \(String(describing: error))")
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId,
            kSecValueData as String: Data(key),
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CryptoError.keychain("biometric save \(status)")
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
            throw CryptoError.keychain("biometric delete \(status)")
        }
    }
}

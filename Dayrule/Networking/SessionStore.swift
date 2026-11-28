import Foundation
import Security

/// Session token + cached unlock material in the Keychain (M2).
///
/// Token and cached account share **one** SecItem (`account: "session"`) so a
/// Mac code-signature change prompts once at launch, not twice (legacy split
/// `token` + `cached` items each asked separately).
///
/// Process-local blob cache: unlock / gate paths call `loadAccount` /
/// `loadToken` many times; without a hit they would re-prompt macOS Keychain
/// for the same item after the coalesced launch read.
struct SessionStore: Sendable {
    private let service = "uk.co.lessknown.dayrule.session"
    /// Combined blob (current).
    private let sessionAccount = "session"
    /// Pre-coalesce Keychain account keys — migrated away on first read/write.
    private let legacyTokenAccount = "token"
    private let legacyCachedAccount = "cached"
    private let cache = BlobCache()

    struct CachedAccount: Codable, Sendable {
        var userId: String
        var email: String
        var saltB64: String
        var kdf: KdfDTO
        var wrappedPassword: WrappedB64
        var deviceWrappedAK: WrappedB64?
        /// AK wrapped under the biometric Keychain key (PLAN §8.3).
        var biometricWrappedAK: WrappedB64?
        /// Device-local passkey PRF unlock material (PLAN §8.4).
        var passkey: PasskeyUnlock?
    }

    struct PasskeyUnlock: Codable, Equatable, Sendable {
        var credentialId: String
        var salt: String
        var wrapped: WrappedB64
    }

    /// One Keychain round-trip for launch (email prefill + Bearer).
    struct SessionSnapshot: Sendable {
        var token: String?
        var account: CachedAccount?
    }

    private struct SessionBlob: Codable, Sendable {
        var token: String?
        var account: CachedAccount?
    }

    func loadSession() throws -> SessionSnapshot {
        let blob = try loadBlob()
        return SessionSnapshot(token: blob.token, account: blob.account)
    }

    func saveToken(_ token: String) throws {
        var blob = try loadBlob()
        blob.token = token
        try saveBlob(blob)
    }

    func loadToken() throws -> String? {
        try loadBlob().token
    }

    func deleteToken() throws {
        var blob = try loadBlob()
        guard blob.token != nil else { return }
        blob.token = nil
        try saveBlob(blob)
    }

    func saveAccount(_ account: CachedAccount) throws {
        var blob = try loadBlob()
        blob.account = account
        try saveBlob(blob)
    }

    func loadAccount() throws -> CachedAccount? {
        try loadBlob().account
    }

    func clear() throws {
        try deleteRaw(account: sessionAccount)
        try deleteRaw(account: legacyTokenAccount)
        try deleteRaw(account: legacyCachedAccount)
        cache.invalidate()
    }

    // MARK: - Combined blob + legacy migration

    private func loadBlob() throws -> SessionBlob {
        switch cache.slot() {
        case .hit(let blob):
            return blob
        case .miss:
            break
        }
        let blob = try loadBlobFromKeychain()
        cache.set(blob)
        return blob
    }

    private func loadBlobFromKeychain() throws -> SessionBlob {
        if let data = try loadRaw(account: sessionAccount) {
            return try JSONDecoder().decode(SessionBlob.self, from: data)
        }
        // Migrate split items written by older builds (two Mac Keychain prompts).
        let legacyToken: String?
        if let data = try loadRaw(account: legacyTokenAccount) {
            legacyToken = String(data: data, encoding: .utf8)
        } else {
            legacyToken = nil
        }
        let legacyAccount: CachedAccount?
        if let data = try loadRaw(account: legacyCachedAccount) {
            legacyAccount = try JSONDecoder().decode(CachedAccount.self, from: data)
        } else {
            legacyAccount = nil
        }
        let blob = SessionBlob(token: legacyToken, account: legacyAccount)
        if blob.token != nil || blob.account != nil {
            // Prefer coalesced item, but never fail the read if migration write
            // fails — unlock still needs the legacy snapshot in memory.
            do {
                try saveBlob(blob)
            } catch {
                // saveBlob already warmed the cache; keep the in-memory blob.
                return blob
            }
        }
        return blob
    }

    private func saveBlob(_ blob: SessionBlob) throws {
        // Drop the item entirely when empty so clear() and empty state match.
        if blob.token == nil, blob.account == nil {
            try deleteRaw(account: sessionAccount)
            try deleteRaw(account: legacyTokenAccount)
            try deleteRaw(account: legacyCachedAccount)
            cache.set(blob)
            return
        }
        let data = try JSONEncoder().encode(blob)
        try saveRaw(account: sessionAccount, data: data)
        // Only drop legacy keys after the combined item is persisted.
        try deleteRaw(account: legacyTokenAccount)
        try deleteRaw(account: legacyCachedAccount)
        cache.set(blob)
    }

    private func saveRaw(account: String, data: Data) throws {
        if MemoryKeychain.enabled {
            MemoryKeychain.save(service: service, account: account, data: data)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        // Update in place when possible — delete-then-add can lose the session
        // if Add fails after Delete.
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CryptoError.keychain("save \(status)") }
    }

    private func loadRaw(account: String) throws -> Data? {
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

    private func deleteRaw(account: String) throws {
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

    private enum Slot {
        case miss
        case hit(SessionBlob)
    }

    /// In-memory hit for the coalesced session blob (avoids repeat Keychain prompts).
    private final class BlobCache: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Slot = .miss

        func slot() -> Slot {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ blob: SessionBlob) {
            lock.lock()
            defer { lock.unlock() }
            value = .hit(blob)
        }

        func invalidate() {
            lock.lock()
            defer { lock.unlock() }
            value = .miss
        }
    }
}

/// Keychain Bearer may be reused only for the same unlocked user (recovery).
enum SessionBinding {
    static func canReuseBearer(unlockedUserId: String, cachedUserId: String?) -> Bool {
        let unlocked = unlockedUserId.lowercased()
        guard let cached = cachedUserId?.lowercased(), !cached.isEmpty else { return false }
        return cached == unlocked
    }
}

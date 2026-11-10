import Clibsodium
import Foundation

/// Owns the account key while unlocked (PLAN §8.1).
actor CryptoActor {
    private var accountKey: SecureBuffer?
    private var syncIdKey: SecureBuffer?
    private var userId: String?
    private let deviceStore = DeviceKeyStore()
    private let biometricStore = BiometricKeyStore()

    var isUnlocked: Bool { accountKey != nil }

    func biometryAvailable() -> Bool { biometricStore.biometryAvailable() }
    func biometryName() -> String { biometricStore.biometryName() }

    func currentUserId() -> String? { userId }

    func lock() {
        accountKey?.clear()
        syncIdKey?.clear()
        accountKey = nil
        syncIdKey = nil
        userId = nil
    }

    private func hold(ak: [UInt8], userId: String) {
        lock()
        self.userId = userId
        accountKey = SecureBuffer(bytes: ak)
        syncIdKey = SecureBuffer(bytes: Primitives.hkdf(ikm: ak, label: Labels.syncId))
    }

    /// Derive AuthKey for login (KEK kept only for the subsequent unwrap).
    func beginLogin(password: String, salt: [UInt8], kdf: KdfParams) throws -> (authKey: [UInt8], kek: [UInt8]) {
        Primitives.ready()
        try kdf.meetFloor()
        let mk = try Primitives.deriveMasterKey(password: password, salt: salt, kdf: kdf)
        let authKey = Primitives.hkdf(ikm: mk, label: Labels.auth)
        let kek = Primitives.hkdf(ikm: mk, label: Labels.kek)
        return (authKey, kek)
    }

    func unlockWithPasswordWrap(
        kek: [UInt8],
        userId: String,
        wrapped: Primitives.Sealed,
        stayUnlocked: Bool
    ) throws -> Primitives.Sealed? {
        let ak = try Primitives.unwrapKey(
            kek: kek,
            wrapped: wrapped,
            label: Labels.wrapUnderKek,
            userId: userId
        )
        hold(ak: ak, userId: userId)
        guard stayUnlocked else { return nil }
        let deviceKey = try deviceStore.loadOrCreate(userId: userId)
        return try Primitives.wrapKey(
            kek: deviceKey,
            key: ak,
            label: Labels.wrapDevice,
            userId: userId
        )
    }

    func unlockFromDeviceWrap(userId: String, wrapped: Primitives.Sealed) throws {
        let deviceKey = try deviceStore.load(userId: userId)
        guard let deviceKey else { throw CryptoError.notUnlocked }
        let ak = try Primitives.unwrapKey(
            kek: deviceKey,
            wrapped: wrapped,
            label: Labels.wrapDevice,
            userId: userId
        )
        hold(ak: ak, userId: userId)
    }

    /// Wrap the in-memory AK under a biometric Keychain key (PLAN §8.3).
    func enableBiometricWrap() throws -> Primitives.Sealed {
        guard let accountKey, let userId else { throw CryptoError.notUnlocked }
        let bioKey = try biometricStore.loadOrCreate(userId: userId)
        return try accountKey.withUnsafeBytes { akBytes in
            try Primitives.wrapKey(
                kek: bioKey,
                keyBytes: akBytes,
                label: Labels.wrapDevice,
                userId: userId
            )
        }
    }

    func unlockFromBiometricWrap(userId: String, wrapped: Primitives.Sealed) throws {
        guard let bioKey = try biometricStore.load(userId: userId) else {
            throw CryptoError.notUnlocked
        }
        let ak = try Primitives.unwrapKey(
            kek: bioKey,
            wrapped: wrapped,
            label: Labels.wrapDevice,
            userId: userId
        )
        hold(ak: ak, userId: userId)
    }

    func disableBiometricWrap(userId: String) throws {
        try biometricStore.delete(userId: userId)
    }

    /// Drop device convenience wraps (stay-unlocked + biometric Keychain keys).
    /// Matches web `keyring.forgetDevice` on sign-out — ciphertext stays on disk.
    func forgetDevice(userId: String) throws {
        try deviceStore.delete(userId: userId)
        try biometricStore.delete(userId: userId)
    }

    /// Remove only the stay-unlocked device key (keep biometric wrap if any).
    func forgetDeviceWrapOnly(userId: String) throws {
        try deviceStore.delete(userId: userId)
    }

    /// Wrap AK under HKDF(PRF, `dayrule/prf-kek/v1`) (PLAN §8.4). Wipes `prf`.
    func wrapForPrf(prf: inout [UInt8]) throws -> Primitives.Sealed {
        guard let accountKey, let userId else { throw CryptoError.notUnlocked }
        defer { Primitives.wipe(&prf) }
        var kek = Primitives.hkdf(ikm: prf, label: Labels.prfKek)
        defer { Primitives.wipe(&kek) }
        return try accountKey.withUnsafeBytes { akBytes in
            try Primitives.wrapKey(
                kek: kek,
                keyBytes: akBytes,
                label: Labels.wrapUnderPrf,
                userId: userId
            )
        }
    }

    /// Unlock with PRF output; wipes `prf` (PLAN §8.4).
    func unlockWithPrf(userId: String, prf: inout [UInt8], wrapped: Primitives.Sealed) throws {
        defer { Primitives.wipe(&prf) }
        var kek = Primitives.hkdf(ikm: prf, label: Labels.prfKek)
        defer { Primitives.wipe(&kek) }
        let ak = try Primitives.unwrapKey(
            kek: kek,
            wrapped: wrapped,
            label: Labels.wrapUnderPrf,
            userId: userId
        )
        hold(ak: ak, userId: userId)
    }

    func unlockFromRecovery(phrase: String, userId: String, wrappedRecovery: Primitives.Sealed) throws {
        let entropy = try Recovery.fromPhrase(phrase)
        let rk = Recovery.recoveryKey(entropy: entropy)
        let ak = try Primitives.unwrapKey(
            kek: rk,
            wrapped: wrappedRecovery,
            label: Labels.wrapRecovery,
            userId: userId
        )
        hold(ak: ak, userId: userId)
    }

    func recoveryProofB64(phrase: String) throws -> String {
        let entropy = try Recovery.fromPhrase(phrase)
        return Base64Std.encode(Recovery.recoveryProof(entropy: entropy))
    }

    /// Local demo account (M1) — kept for offline smoke without an API.
    @discardableResult
    func createLocalDemo(password: String, userId: String, salt: [UInt8], kdf: KdfParams = .default) throws -> UnlockResult {
        try kdf.meetFloor()
        let mk = try Primitives.deriveMasterKey(password: password, salt: salt, kdf: kdf)
        let authKey = Primitives.hkdf(ikm: mk, label: Labels.auth)
        let kek = Primitives.hkdf(ikm: mk, label: Labels.kek)
        let ak = Primitives.randomBytes(CryptoConstants.keyBytes)
        let wrappedPw = try Primitives.wrapKey(kek: kek, key: ak, label: Labels.wrapUnderKek, userId: userId)
        let entropy = Recovery.newEntropy()
        let rk = Recovery.recoveryKey(entropy: entropy)
        let wrappedRecovery = try Primitives.wrapKey(kek: rk, key: ak, label: Labels.wrapRecovery, userId: userId)
        let words = try Recovery.toPhrase(entropy)
        let proof = Recovery.recoveryProof(entropy: entropy)
        let deviceKey = try deviceStore.loadOrCreate(userId: userId)
        let wrappedDevice = try Primitives.wrapKey(kek: deviceKey, key: ak, label: Labels.wrapDevice, userId: userId)
        hold(ak: ak, userId: userId)
        return UnlockResult(
            authKey: authKey,
            wrappedPassword: wrappedPw,
            wrappedRecovery: wrappedRecovery,
            wrappedDevice: wrappedDevice,
            recoveryWords: words,
            recoveryProof: proof,
            salt: salt,
            kdf: kdf
        )
    }

    func syncId(for key: String) throws -> String {
        guard let syncIdKey else { throw CryptoError.notUnlocked }
        var mac = [UInt8](repeating: 0, count: Int(crypto_auth_hmacsha256_bytes()))
        let msg = Array(key.utf8)
        let status = try syncIdKey.withUnsafeBytes { keyRaw -> Int32 in
            mac.withUnsafeMutableBytes { macRaw in
                msg.withUnsafeBytes { msgRaw in
                    crypto_auth_hmacsha256(
                        macRaw.bindMemory(to: UInt8.self).baseAddress!,
                        msgRaw.bindMemory(to: UInt8.self).baseAddress!,
                        UInt64(msg.count),
                        keyRaw.bindMemory(to: UInt8.self).baseAddress!
                    )
                }
            }
        }
        guard status == 0 else { throw CryptoError.sealFailed }
        var truncated = Array(mac.prefix(16))
        truncated[6] = (truncated[6] & 0x0F) | 0x40
        truncated[8] = (truncated[8] & 0x3F) | 0x80
        let hex = Hex.encode(truncated)
        let p = Array(hex)
        return String(p[0..<8]) + "-" + String(p[8..<12]) + "-" + String(p[12..<16])
            + "-" + String(p[16..<20]) + "-" + String(p[20..<32])
    }

    /// Local GRDB row AAD is the entity key (`todos/<id>`), not `sync/<id>`.
    func encryptLocal(recordId: String, jsonUTF8: [UInt8], keyId: Int = 1) throws -> EnvelopeB64 {
        guard let accountKey, let userId else { throw CryptoError.notUnlocked }
        let meta = Primitives.RecordMeta(
            userId: userId,
            recordId: recordId,
            schemaVersion: 1,
            keyId: keyId
        )
        let env = try accountKey.withUnsafeBytes { akBytes in
            try Primitives.encryptRecordJSON(akBytes: akBytes, meta: meta, jsonUTF8: jsonUTF8)
        }
        return EnvelopeB64(env)
    }

    func decryptLocal(recordId: String, envelope: EnvelopeB64) throws -> [UInt8] {
        guard let accountKey, let userId else { throw CryptoError.notUnlocked }
        let meta = Primitives.RecordMeta(
            userId: userId,
            recordId: recordId,
            schemaVersion: 1,
            keyId: envelope.keyId
        )
        return try accountKey.withUnsafeBytes { akBytes in
            try Primitives.decryptRecordJSON(akBytes: akBytes, meta: meta, env: try envelope.envelope())
        }
    }

    /// Encrypt a sync wire payload `{k,v}` / `{k,d}` under AAD `sync/<wireId>`.
    func encryptSyncPayload(
        key: String,
        value: [String: JSONValue]?,
        deleted: String?,
        keyId: Int = 1
    ) throws -> (id: String, env: EnvelopeB64) {
        guard let accountKey, let userId else { throw CryptoError.notUnlocked }
        let id = try syncId(for: key)
        var payload: [String: Any] = ["k": key]
        if let deleted {
            payload["d"] = deleted
        } else if let value {
            payload["v"] = JSONDict.toAny(value)
        } else {
            throw CryptoError.sealFailed
        }
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let meta = Primitives.RecordMeta(
            userId: userId,
            recordId: "sync/\(id)",
            schemaVersion: 1,
            keyId: keyId
        )
        let env = try accountKey.withUnsafeBytes { akBytes in
            try Primitives.encryptRecordJSON(akBytes: akBytes, meta: meta, jsonUTF8: [UInt8](json))
        }
        return (id, EnvelopeB64(env))
    }

    func decryptSyncPayload(_ rec: WireRecord) throws -> SyncPayload? {
        guard let accountKey, let userId else { throw CryptoError.notUnlocked }
        // Wire ids are lowercase UUID form (PLAN §8.5); normalize before AAD.
        let wireId = rec.id.lowercased()
        let meta = Primitives.RecordMeta(
            userId: userId,
            recordId: "sync/\(wireId)",
            schemaVersion: 1,
            keyId: rec.keyId
        )
        let env = Primitives.Envelope(
            alg: rec.alg,
            keyId: rec.keyId,
            nonce: try Base64Std.decode(rec.nonce),
            ciphertext: try Base64Std.decode(rec.ciphertext)
        )
        let plain = try accountKey.withUnsafeBytes { akBytes in
            try Primitives.decryptRecordJSON(akBytes: akBytes, meta: meta, env: env)
        }
        let obj = try JSONSerialization.jsonObject(with: Data(plain)) as? [String: Any]
        guard let key = obj?["k"] as? String else { return nil }
        let expected = try syncId(for: key)
        guard expected == rec.id.lowercased() else { throw CryptoError.openFailed }
        if let deleted = obj?["d"] as? String {
            return SyncPayload(key: key, value: nil, deleted: deleted)
        }
        guard let value = obj?["v"] as? [String: Any] else { return nil }
        return SyncPayload(key: key, value: JSONDict.fromAny(value), deleted: nil)
    }

    func decryptSyncRecord(_ rec: WireRecord) throws -> VaultEntity? {
        guard let payload = try decryptSyncPayload(rec), payload.deleted == nil else { return nil }
        return VaultEntity(key: payload.key, title: payload.title, type: payload.type)
    }
}

/// Decrypted sync payload (`{k,v}` or tombstone `{k,d}`). `value` is nil for tombstones.
struct SyncPayload: Sendable {
    var key: String
    var value: [String: JSONValue]?
    var deleted: String?

    var title: String {
        guard let value else { return key }
        if let t = value["title"]?.stringValue { return t }
        let type = value["type"]?.stringValue
            ?? key.split(separator: "/").first.map(String.init)
            ?? "?"
        return type == "settings" ? "Settings" : key
    }

    var type: String {
        value?["type"]?.stringValue
            ?? key.split(separator: "/").first.map(String.init)
            ?? "?"
    }

    var valueAny: [String: Any]? {
        value.map(JSONDict.toAny)
    }
}

struct UnlockResult: Sendable {
    var authKey: [UInt8]
    var wrappedPassword: Primitives.Sealed
    var wrappedRecovery: Primitives.Sealed
    var wrappedDevice: Primitives.Sealed
    var recoveryWords: [String]
    var recoveryProof: [UInt8]
    var salt: [UInt8]
    var kdf: KdfParams
}

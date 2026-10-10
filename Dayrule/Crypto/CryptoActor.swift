import Foundation

/// Owns the account key while unlocked (PLAN §8.1).
actor CryptoActor {
    private var accountKey: SecureBuffer?
    private var syncIdKey: SecureBuffer?
    private var userId: String?
    private let deviceStore = DeviceKeyStore()

    var isUnlocked: Bool { accountKey != nil }

    func lock() {
        accountKey?.clear()
        syncIdKey?.clear()
        accountKey = nil
        syncIdKey = nil
        userId = nil
    }

    /// Local demo unlock for M1: derive keys from password, create AK, wrap under device key.
    @discardableResult
    func unlockWithPassword(
        password: String,
        userId: String,
        salt: [UInt8],
        kdf: KdfParams = .default,
        existingAccountKey: [UInt8]? = nil
    ) async throws -> UnlockResult {
        try kdf.meetFloor()
        let mk = try Primitives.deriveMasterKey(password: password, salt: salt, kdf: kdf)
        let authKey = Primitives.hkdf(ikm: mk, label: Labels.auth)
        let kek = Primitives.hkdf(ikm: mk, label: Labels.kek)
        let ak = existingAccountKey ?? Primitives.randomBytes(CryptoConstants.keyBytes)
        let wrappedPw = try Primitives.wrapKey(
            kek: kek,
            key: ak,
            label: Labels.wrapUnderKek,
            userId: userId
        )

        let entropy = Recovery.newEntropy()
        let rk = Recovery.recoveryKey(entropy: entropy)
        let wrappedRecovery = try Primitives.wrapKey(
            kek: rk,
            key: ak,
            label: Labels.wrapRecovery,
            userId: userId
        )
        let words = try Recovery.toPhrase(entropy)
        let proof = Recovery.recoveryProof(entropy: entropy)

        let deviceKey = try deviceStore.loadOrCreate(userId: userId)
        let wrappedDevice = try Primitives.wrapKey(
            kek: deviceKey,
            key: ak,
            label: Labels.wrapDevice,
            userId: userId
        )

        lock()
        self.userId = userId
        accountKey = SecureBuffer(bytes: ak)
        syncIdKey = SecureBuffer(bytes: Primitives.hkdf(ikm: ak, label: Labels.syncId))

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

    func unlockFromDeviceWrap(userId: String, wrapped: Primitives.Sealed) throws {
        let deviceKey = try deviceStore.load(userId: userId)
        guard let deviceKey else { throw CryptoError.notUnlocked }
        let ak = try Primitives.unwrapKey(
            kek: deviceKey,
            wrapped: wrapped,
            label: Labels.wrapDevice,
            userId: userId
        )
        lock()
        self.userId = userId
        accountKey = SecureBuffer(bytes: ak)
        syncIdKey = SecureBuffer(bytes: Primitives.hkdf(ikm: ak, label: Labels.syncId))
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
        lock()
        self.userId = userId
        accountKey = SecureBuffer(bytes: ak)
        syncIdKey = SecureBuffer(bytes: Primitives.hkdf(ikm: ak, label: Labels.syncId))
    }

    func encryptRecordJSON(meta: Primitives.RecordMeta, jsonUTF8: [UInt8], nonce: [UInt8]? = nil) throws -> Primitives.Envelope {
        guard let ak = accountKey?.bytes else { throw CryptoError.notUnlocked }
        return try Primitives.encryptRecordJSON(ak: ak, meta: meta, jsonUTF8: jsonUTF8, nonce: nonce)
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

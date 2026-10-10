import Foundation

/// Wire labels from `dayrule/web/src/crypto/primitives.ts` (PLAN §8.5).
enum Labels {
    static let auth = "dayrule/auth/v1"
    static let kek = "dayrule/kek/v1"
    static let recovery = "dayrule/recovery/v1"
    static let recoveryProof = "dayrule/recovery-proof/v1"
    static let wrapUnderKek = "dayrule/wrap/password/v1"
    static let wrapRecovery = "dayrule/wrap/recovery/v1"
    static let wrapDevice = "dayrule/wrap/device/v1"
    static let wrapUnderPrf = "dayrule/wrap/prf/v1"
    static let record = "dayrule/record/v1"
    static let syncId = "dayrule/sync-id/v1"
    static let prfKek = "dayrule/prf-kek/v1"
}

enum CryptoConstants {
    static let keyBytes = 32
    static let nonceBytes = 24
    static let saltBytes = 16
    static let alg = 1
}

struct KdfParams: Codable, Equatable, Sendable {
    var v: Int
    var ops: UInt32
    /// Argon2id memory in **bytes**.
    var mem: UInt32

    static let `default` = KdfParams(v: 1, ops: 3, mem: 64 * 1024 * 1024)

    /// Refuse weak or absurd server-supplied params (PLAN §8.6).
    func meetFloor() throws {
        guard v == 1 else { throw CryptoError.kdfRejected("unsupported KDF version") }
        guard ops >= 3, ops <= 10 else { throw CryptoError.kdfRejected("ops out of range") }
        guard mem >= 64 * 1024 * 1024, mem <= 1024 * 1024 * 1024 else {
            throw CryptoError.kdfRejected("mem out of range")
        }
    }
}

enum CryptoError: Error, LocalizedError, Equatable {
    case saltLength
    case keyLength
    case sealFailed
    case openFailed
    case badPadding
    case unsupportedAlg(Int)
    case keyIdMismatch
    case kdfRejected(String)
    case recoveryPhraseInvalid
    case notUnlocked
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .saltLength: "Salt must be 16 bytes."
        case .keyLength: "Key must be 32 bytes."
        case .sealFailed: "Encryption failed."
        case .openFailed: "Decryption failed."
        case .badPadding: "Bad padding."
        case .unsupportedAlg(let n): "Unsupported algorithm suite \(n)."
        case .keyIdMismatch: "Key id mismatch."
        case .kdfRejected(let reason): "KDF params rejected: \(reason)."
        case .recoveryPhraseInvalid: "That recovery phrase isn’t right."
        case .notUnlocked: "Vault is locked."
        case .keychain(let s): "Keychain error: \(s)."
        }
    }
}

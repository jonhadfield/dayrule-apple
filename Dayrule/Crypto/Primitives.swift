import Clibsodium
import CryptoKit
import Foundation

/// Cryptographic building blocks matching `dayrule/web/src/crypto/primitives.ts`.
enum Primitives {
    static func ready() {
        _ = sodium_init()
    }

    static func randomBytes(_ n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n)
        out.withUnsafeMutableBytes { buf in
            randombytes_buf(buf.baseAddress!, n)
        }
        return out
    }

    /// Password → 32-byte MasterKey. Unicode is NFKC-normalised first.
    static func deriveMasterKey(password: String, salt: [UInt8], kdf: KdfParams) throws -> [UInt8] {
        try kdf.meetFloor()
        guard salt.count == CryptoConstants.saltBytes else { throw CryptoError.saltLength }
        let normalized = password.precomposedStringWithCompatibilityMapping
        let passInt8 = Array(normalized.utf8).map(Int8.init(bitPattern:))
        var out = [UInt8](repeating: 0, count: CryptoConstants.keyBytes)
        let status = out.withUnsafeMutableBytes { outRaw -> Int32 in
            passInt8.withUnsafeBytes { passRaw in
                salt.withUnsafeBytes { saltRaw in
                    crypto_pwhash(
                        outRaw.bindMemory(to: UInt8.self).baseAddress!,
                        UInt64(CryptoConstants.keyBytes),
                        passRaw.bindMemory(to: Int8.self).baseAddress!,
                        UInt64(passInt8.count),
                        saltRaw.bindMemory(to: UInt8.self).baseAddress!,
                        UInt64(kdf.ops),
                        Int(kdf.mem),
                        crypto_pwhash_alg_argon2id13()
                    )
                }
            }
        }
        guard status == 0 else { throw CryptoError.sealFailed }
        return out
    }

    /// Best-effort wipe of a mutable byte buffer (libsodium `sodium_memzero`).
    static func wipe(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { buf in
            if let base = buf.baseAddress {
                sodium_memzero(base, buf.count)
            }
        }
        bytes = []
    }

    /// HKDF-SHA256 with empty salt and a text label as `info`.
    static func hkdf(ikm: [UInt8], label: String, length: Int = CryptoConstants.keyBytes) -> [UInt8] {
        let input = SymmetricKey(data: Data(ikm))
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            salt: Data(),
            info: Data(label.utf8),
            outputByteCount: length
        )
        return derived.withUnsafeBytes { Array($0) }
    }

    struct Sealed: Equatable, Sendable {
        var nonce: [UInt8]
        var ciphertext: [UInt8]
    }

    static func seal(
        key: [UInt8],
        plaintext: [UInt8],
        aad: [UInt8],
        nonce: [UInt8]? = nil
    ) throws -> Sealed {
        guard key.count == CryptoConstants.keyBytes else { throw CryptoError.keyLength }
        let n = nonce ?? randomBytes(CryptoConstants.nonceBytes)
        guard n.count == CryptoConstants.nonceBytes else { throw CryptoError.sealFailed }

        var ciphertext = [UInt8](
            repeating: 0,
            count: plaintext.count + Int(crypto_aead_xchacha20poly1305_ietf_abytes())
        )
        var cipherLen: UInt64 = 0

        let status: Int32 = ciphertext.withUnsafeMutableBytes { cRaw in
            plaintext.withUnsafeBytes { pRaw in
                aad.withUnsafeBytes { aRaw in
                    n.withUnsafeBytes { nRaw in
                        key.withUnsafeBytes { kRaw in
                            crypto_aead_xchacha20poly1305_ietf_encrypt(
                                cRaw.bindMemory(to: UInt8.self).baseAddress!,
                                &cipherLen,
                                pRaw.bindMemory(to: UInt8.self).baseAddress!,
                                UInt64(plaintext.count),
                                aRaw.bindMemory(to: UInt8.self).baseAddress!,
                                UInt64(aad.count),
                                nil,
                                nRaw.bindMemory(to: UInt8.self).baseAddress!,
                                kRaw.bindMemory(to: UInt8.self).baseAddress!
                            )
                        }
                    }
                }
            }
        }
        guard status == 0 else { throw CryptoError.sealFailed }
        ciphertext.removeSubrange(Int(cipherLen)..<ciphertext.count)
        return Sealed(nonce: n, ciphertext: ciphertext)
    }

    static func open(key: [UInt8], sealed: Sealed, aad: [UInt8]) throws -> [UInt8] {
        guard key.count == CryptoConstants.keyBytes else { throw CryptoError.keyLength }
        guard sealed.nonce.count == CryptoConstants.nonceBytes else { throw CryptoError.openFailed }
        let tag = Int(crypto_aead_xchacha20poly1305_ietf_abytes())
        guard sealed.ciphertext.count >= tag else { throw CryptoError.openFailed }

        var message = [UInt8](repeating: 0, count: sealed.ciphertext.count - tag)
        var messageLen: UInt64 = 0

        let status: Int32 = message.withUnsafeMutableBytes { mRaw in
            sealed.ciphertext.withUnsafeBytes { cRaw in
                aad.withUnsafeBytes { aRaw in
                    sealed.nonce.withUnsafeBytes { nRaw in
                        key.withUnsafeBytes { kRaw in
                            crypto_aead_xchacha20poly1305_ietf_decrypt(
                                mRaw.bindMemory(to: UInt8.self).baseAddress!,
                                &messageLen,
                                nil,
                                cRaw.bindMemory(to: UInt8.self).baseAddress!,
                                UInt64(sealed.ciphertext.count),
                                aRaw.bindMemory(to: UInt8.self).baseAddress!,
                                UInt64(aad.count),
                                nRaw.bindMemory(to: UInt8.self).baseAddress!,
                                kRaw.bindMemory(to: UInt8.self).baseAddress!
                            )
                        }
                    }
                }
            }
        }
        guard status == 0 else { throw CryptoError.openFailed }
        message.removeSubrange(Int(messageLen)..<message.count)
        return message
    }

    static func wrapKey(
        kek: [UInt8],
        key: [UInt8],
        label: String,
        userId: String,
        nonce: [UInt8]? = nil
    ) throws -> Sealed {
        try seal(key: kek, plaintext: key, aad: Array("\(label)|\(userId)".utf8), nonce: nonce)
    }

    static func unwrapKey(
        kek: [UInt8],
        wrapped: Sealed,
        label: String,
        userId: String
    ) throws -> [UInt8] {
        try open(key: kek, sealed: wrapped, aad: Array("\(label)|\(userId)".utf8))
    }

    private static let smallBuckets = [256, 512, 1024, 2048]

    static func bucketSize(_ n: Int) -> Int {
        for b in smallBuckets where n <= b { return b }
        return Int(ceil(Double(n) / 4096.0)) * 4096
    }

    static func pad(_ data: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bucketSize(data.count + 1))
        out.replaceSubrange(0..<data.count, with: data)
        out[data.count] = 0x80
        return out
    }

    static func unpad(_ data: [UInt8]) throws -> [UInt8] {
        var i = data.count - 1
        while i >= 0, data[i] == 0 { i -= 1 }
        guard i >= 0, data[i] == 0x80 else { throw CryptoError.badPadding }
        return Array(data[0..<i])
    }

    struct RecordMeta: Equatable, Sendable {
        var userId: String
        var recordId: String
        var schemaVersion: Int
        var keyId: Int
    }

    struct Envelope: Equatable, Sendable {
        var alg: Int
        var keyId: Int
        var nonce: [UInt8]
        var ciphertext: [UInt8]
    }

    static func recordAad(_ m: RecordMeta) -> [UInt8] {
        Array(
            "\(Labels.record)|\(m.userId)|\(m.recordId)|v\(m.schemaVersion)|alg\(CryptoConstants.alg)|key\(m.keyId)"
                .utf8
        )
    }

    static func encryptRecordJSON(
        ak: [UInt8],
        meta: RecordMeta,
        jsonUTF8: [UInt8],
        nonce: [UInt8]? = nil
    ) throws -> Envelope {
        let sealed = try seal(key: ak, plaintext: pad(jsonUTF8), aad: recordAad(meta), nonce: nonce)
        return Envelope(alg: CryptoConstants.alg, keyId: meta.keyId, nonce: sealed.nonce, ciphertext: sealed.ciphertext)
    }

    static func decryptRecordJSON(ak: [UInt8], meta: RecordMeta, env: Envelope) throws -> [UInt8] {
        guard env.alg == CryptoConstants.alg else { throw CryptoError.unsupportedAlg(env.alg) }
        guard env.keyId == meta.keyId else { throw CryptoError.keyIdMismatch }
        return try unpad(open(key: ak, sealed: Sealed(nonce: env.nonce, ciphertext: env.ciphertext), aad: recordAad(meta)))
    }
}

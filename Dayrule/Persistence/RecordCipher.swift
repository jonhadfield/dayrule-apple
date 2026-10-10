import Foundation

/// Encrypt/decrypt entity JSON for local GRDB rows (AAD = collection/id).
protocol RecordCipher: Sendable {
    func encrypt(recordId: String, jsonUTF8: [UInt8]) async throws -> EnvelopeB64
    func decrypt(recordId: String, envelope: EnvelopeB64) async throws -> [UInt8]
}

/// Test double: stores plaintext as base64 ciphertext (not for production).
struct PassthroughCipher: RecordCipher {
    func encrypt(recordId: String, jsonUTF8: [UInt8]) async throws -> EnvelopeB64 {
        EnvelopeB64(
            alg: CryptoConstants.alg,
            keyId: 1,
            nonce: Base64Std.encode([UInt8](repeating: 0, count: 24)),
            ciphertext: Base64Std.encode(jsonUTF8)
        )
    }

    func decrypt(recordId: String, envelope: EnvelopeB64) async throws -> [UInt8] {
        try Base64Std.decode(envelope.ciphertext)
    }
}

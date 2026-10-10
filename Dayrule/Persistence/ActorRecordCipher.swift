import Foundation

/// `RecordCipher` backed by the unlocked `CryptoActor` (local AAD = entity key).
struct ActorRecordCipher: RecordCipher {
    let crypto: CryptoActor

    func encrypt(recordId: String, jsonUTF8: [UInt8]) async throws -> EnvelopeB64 {
        try await crypto.encryptLocal(recordId: recordId, jsonUTF8: jsonUTF8)
    }

    func decrypt(recordId: String, envelope: EnvelopeB64) async throws -> [UInt8] {
        try await crypto.decryptLocal(recordId: recordId, envelope: envelope)
    }
}

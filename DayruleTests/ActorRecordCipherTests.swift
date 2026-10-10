import Foundation
import Testing
@testable import Dayrule

@Suite("ActorRecordCipher")
struct ActorRecordCipherTests {
    private func unlock(_ crypto: CryptoActor) async throws {
        Primitives.ready()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/shared/crypto-vectors.json")
        let vectors = try JSONDecoder().decode(CryptoVectorsFile.self, from: Data(contentsOf: url))
        let (_, kek) = try await crypto.beginLogin(
            password: vectors.input.password,
            salt: try Hex.decode(vectors.input.salt),
            kdf: vectors.input.kdf
        )
        _ = try await crypto.unlockWithPasswordWrap(
            kek: kek,
            userId: vectors.input.userId,
            wrapped: Primitives.Sealed(
                nonce: try Hex.decode(vectors.input.wrapNonce),
                ciphertext: try Hex.decode(vectors.output.wrappedAccountKeyPassword)
            ),
            stayUnlocked: false
        )
    }

    @Test func localEncryptDecryptRoundTrip() async throws {
        let crypto = CryptoActor()
        try await unlock(crypto)
        let cipher = ActorRecordCipher(crypto: crypto)
        let json = Array(#"{"type":"todo","title":"Milk","id":"t1"}"#.utf8)
        let env = try await cipher.encrypt(recordId: "todos/t1", jsonUTF8: json)
        #expect(env.alg == CryptoConstants.alg)
        let plain = try await cipher.decrypt(recordId: "todos/t1", envelope: env)
        #expect(plain == json)
    }

    @Test func localAadRejectsSwappedRecordId() async throws {
        let crypto = CryptoActor()
        try await unlock(crypto)
        let cipher = ActorRecordCipher(crypto: crypto)
        let json = Array(#"{"type":"todo","title":"Milk"}"#.utf8)
        let env = try await cipher.encrypt(recordId: "todos/t1", jsonUTF8: json)
        await #expect(throws: CryptoError.self) {
            _ = try await cipher.decrypt(recordId: "todos/t2", envelope: env)
        }
    }
}

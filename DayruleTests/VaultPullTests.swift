import Foundation
import Testing
@testable import Dayrule

/// Read-only vault proof (PLAN §14.1 M2): decrypt a web-shaped sync record
/// (`{k,v}` plaintext, AAD `sync/<id>`) written with the shared vector account key.
@Suite("Vault pull decrypt")
struct VaultPullTests {
    private func loadVectors() throws -> CryptoVectorsFile {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/shared/crypto-vectors.json")
        return try JSONDecoder().decode(CryptoVectorsFile.self, from: Data(contentsOf: url))
    }

    private func unlockFromVectors(_ crypto: CryptoActor) async throws -> CryptoVectorsFile {
        Primitives.ready()
        let vectors = try loadVectors()
        let input = vectors.input
        let expected = vectors.output
        let (_, kek) = try await crypto.beginLogin(
            password: input.password,
            salt: try Hex.decode(input.salt),
            kdf: input.kdf
        )
        _ = try await crypto.unlockWithPasswordWrap(
            kek: kek,
            userId: input.userId,
            wrapped: Primitives.Sealed(
                nonce: try Hex.decode(input.wrapNonce),
                ciphertext: try Hex.decode(expected.wrappedAccountKeyPassword)
            ),
            stayUnlocked: false
        )
        return vectors
    }

    /// Build a wire record the way the web sync engine does (engine.ts).
    private func webShapedTodoRecord(
        crypto: CryptoActor,
        key: String,
        title: String
    ) async throws -> WireRecord {
        let value: [String: JSONValue] = [
            "type": .string("todo"),
            "title": .string(title),
            "notes": .string("semi-skimmed"),
            "tonight": .bool(false),
        ]
        let (id, envB64) = try await crypto.encryptSyncPayload(
            key: key,
            value: value,
            deleted: nil
        )
        let env = try envB64.envelope()
        return WireRecord(
            id: id,
            seq: 1,
            alg: env.alg,
            keyId: env.keyId,
            nonce: Base64Std.encode(env.nonce),
            ciphertext: Base64Std.encode(env.ciphertext),
            tombstone: nil
        )
    }

    @Test("pull materialize decrypts web-shaped vault titles and counts")
    func materializeWebShapedVault() async throws {
        let crypto = CryptoActor()
        let vectors = try await unlockFromVectors(crypto)

        let todo = try await webShapedTodoRecord(
            crypto: crypto,
            key: "todos/\(vectors.input.recordId)",
            title: "Buy milk"
        )
        let unknownAlg = WireRecord(
            id: "00000000-0000-4000-8000-000000000099",
            seq: 2,
            alg: 99,
            keyId: 1,
            nonce: todo.nonce,
            ciphertext: todo.ciphertext,
            tombstone: nil
        )
        let tomb = WireRecord(
            id: "00000000-0000-4000-8000-000000000098",
            seq: 3,
            alg: CryptoConstants.alg,
            keyId: 1,
            nonce: todo.nonce,
            ciphertext: todo.ciphertext,
            tombstone: true
        )

        let snap = try await VaultPull.materialize(
            records: [todo, unknownAlg, tomb],
            crypto: crypto
        )

        #expect(snap.recordCount == 3)
        #expect(snap.skippedUnknownAlg == 1)
        #expect(snap.counts["todos"] == 1)
        #expect(snap.entities.count == 1)
        #expect(snap.entities[0].title == "Buy milk")
        #expect(snap.entities[0].type == "todo")
        #expect(snap.entities[0].key == "todos/\(vectors.input.recordId)")
    }

    @Test("sync AAD rejects uppercase userId")
    func uppercaseUserIdAadFails() async throws {
        let crypto = CryptoActor()
        let vectors = try await unlockFromVectors(crypto)
        let key = "todos/\(vectors.input.recordId)"
        let id = try await crypto.syncId(for: key)
        let payload = try JSONSerialization.data(
            withJSONObject: ["k": key, "v": ["type": "todo", "title": "x"]] as [String: Any],
            options: [.sortedKeys]
        )
        let badMeta = Primitives.RecordMeta(
            userId: vectors.input.userId.uppercased(),
            recordId: "sync/\(id)",
            schemaVersion: 1,
            keyId: 1
        )
        let env = try Primitives.encryptRecordJSON(
            ak: try Hex.decode(vectors.input.accountKey),
            meta: badMeta,
            jsonUTF8: [UInt8](payload),
            nonce: try Hex.decode(vectors.input.recordNonce)
        )
        let rec = WireRecord(
            id: id,
            seq: 1,
            alg: env.alg,
            keyId: env.keyId,
            nonce: Base64Std.encode(env.nonce),
            ciphertext: Base64Std.encode(env.ciphertext),
            tombstone: nil
        )
        await #expect(throws: CryptoError.openFailed) {
            try await crypto.decryptSyncRecord(rec)
        }
    }
}

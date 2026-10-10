import Foundation
import Testing
@testable import Dayrule

@Suite("CipherStore")
struct CipherStoreTests {
    @Test func replaceAllAndLoadRoundTrip() async throws {
        let db = try AppDatabase.openInMemory()
        let store = CipherStore(dbQueue: db, cipher: PassthroughCipher())
        var e = Entities.empty()
        e.todos["t1"] = EntityJSON.decodeTodo([
            "type": "todo",
            "id": "t1",
            "createdAt": "2026-10-01T09:00:00.000Z",
            "updatedAt": "2026-10-01T09:00:00.000Z",
            "title": "Buy milk",
            "notes": "",
            "status": "open",
            "start": "inbox",
            "tonight": false,
            "tagIds": [] as [String],
            "order": "a0",
            "secretExtra": "keep",
        ], id: "t1")
        try await store.replaceAll(e)
        #expect(try await store.isEmpty() == false)

        let loaded = try await store.load()
        #expect(loaded.todos["t1"]?.title == "Buy milk")
        #expect(loaded.todos["t1"]?.unknown["secretExtra"]?.stringValue == "keep")
    }

    @Test func applyLocalEnqueuesOutbox() async throws {
        let db = try AppDatabase.openInMemory()
        let store = CipherStore(dbQueue: db, cipher: PassthroughCipher())
        let after = JSONDict.fromAny([
            "type": "todo",
            "id": "t2",
            "createdAt": "2026-10-01T09:00:00.000Z",
            "updatedAt": "2026-10-01T09:00:00.000Z",
            "title": "Task",
            "notes": "",
            "status": "open",
            "start": "inbox",
            "tonight": false,
            "tagIds": [] as [String],
            "order": "a0",
        ])
        try await store.applyLocal([
            .entity(collection: .todos, id: "t2", before: nil, after: after, hlc: "k00000001-0001-dev1"),
        ])
        let box = try await store.outbox(limit: 10)
        #expect(box.map(\.key) == ["todos/t2"])
        let loaded = try await store.load()
        #expect(loaded.todos["t2"]?.title == "Task")
    }

    @Test func sqliteHasNoPlaintextNeedle() async throws {
        let db = try AppDatabase.openInMemory()
        let secure = CipherStore(dbQueue: db, cipher: GarbleCipher())
        var e = Entities.empty()
        e.todos["t1"] = EntityJSON.decodeTodo([
            "type": "todo",
            "id": "t1",
            "createdAt": "2026-10-01T09:00:00.000Z",
            "updatedAt": "2026-10-01T09:00:00.000Z",
            "title": "NEEDLE_PLAINTEXT_XYZ",
            "notes": "",
            "status": "open",
            "start": "inbox",
            "tonight": false,
            "tagIds": [] as [String],
            "order": "a0",
        ], id: "t1")
        try await secure.replaceAll(e)
        let dump = try await db.read { db in
            try String.fetchAll(db, sql: "SELECT ciphertext FROM records").joined()
        }
        #expect(!dump.contains("NEEDLE_PLAINTEXT_XYZ"))
        let loaded = try await secure.load()
        #expect(loaded.todos["t1"]?.title == "NEEDLE_PLAINTEXT_XYZ")
    }
}

/// XOR garble so the DB dump doesn't contain the title substring.
private struct GarbleCipher: RecordCipher {
    func encrypt(recordId: String, jsonUTF8: [UInt8]) async throws -> EnvelopeB64 {
        EnvelopeB64(
            alg: CryptoConstants.alg,
            keyId: 1,
            nonce: Base64Std.encode([UInt8](repeating: 7, count: 24)),
            ciphertext: Base64Std.encode(jsonUTF8.map { $0 ^ 0x5A })
        )
    }

    func decrypt(recordId: String, envelope: EnvelopeB64) async throws -> [UInt8] {
        try Base64Std.decode(envelope.ciphertext).map { $0 ^ 0x5A }
    }
}

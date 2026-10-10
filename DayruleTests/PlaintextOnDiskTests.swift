import Foundation
import Testing
@testable import Dayrule

/// On-disk ciphertext store must not contain needle strings (PLAN §14.1).
@Suite("Plaintext on disk")
struct PlaintextOnDiskTests {
    private let needle = "NEEDLE_ONDISK_PLAINTEXT_XYZ_7f3a"

    @Test func sqliteWalAndShmHaveNoPlaintextNeedle() async throws {
        Primitives.ready()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dayrule-plaintext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("data.sqlite")
        let crypto = CryptoActor()
        try await unlock(crypto)
        let db = try AppDatabase.open(at: dbURL)
        let store = CipherStore(dbQueue: db, cipher: ActorRecordCipher(crypto: crypto))

        var e = Entities.empty()
        e.todos["t1"] = EntityJSON.decodeTodo([
            "type": "todo",
            "id": "t1",
            "createdAt": "2026-10-01T09:00:00.000Z",
            "updatedAt": "2026-10-01T09:00:00.000Z",
            "title": needle,
            "notes": "notes \(needle)",
            "status": "open",
            "start": "inbox",
            "tonight": false,
            "tagIds": [] as [String],
            "order": "a0",
        ], id: "t1")
        try await store.replaceAll(e)
        let loaded = try await store.load()
        #expect(loaded.todos["t1"]?.title == needle)

        // Release the queue so WAL/main are stable to read as files.
        try db.close()

        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: dbURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            #expect(!fileContainsNeedle(url), "found needle in \(url.lastPathComponent)")
        }
    }

    private func unlock(_ crypto: CryptoActor) async throws {
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

    private func fileContainsNeedle(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let plain = Data(needle.utf8)
        if data.range(of: plain) != nil { return true }
        let std = Data(needle.utf8).base64EncodedString()
        if data.range(of: Data(std.utf8)) != nil { return true }
        let urlSafe = Data(needle.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        if data.range(of: Data(urlSafe.utf8)) != nil { return true }
        return false
    }
}

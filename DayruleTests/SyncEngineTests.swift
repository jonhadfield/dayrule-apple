import Foundation
import Testing
@testable import Dayrule

@Suite("SyncEngine")
@MainActor
struct SyncEngineTests {
    private final class MockNet: SyncTransport, @unchecked Sendable {
        var pullPages: [Result<PullResponse, Error>] = []
        var pullCalls = 0
        var pushHandler: ([PushWireRecord]) -> PushResponse = { _ in
            PushResponse(results: [], head: 0)
        }
        var lastPush: [PushWireRecord] = []

        func pull(since: Int64, full: Bool) async throws -> PullResponse {
            defer { pullCalls += 1 }
            guard pullCalls < pullPages.count else {
                return PullResponse(records: [], cursor: since, hasMore: false)
            }
            switch pullPages[pullCalls] {
            case .success(let page): return page
            case .failure(let err): throw err
            }
        }

        func push(_ records: [PushWireRecord]) async throws -> PushResponse {
            lastPush = records
            return pushHandler(records)
        }
    }

    private func unlockCrypto() async throws -> CryptoActor {
        Primitives.ready()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/shared/crypto-vectors.json")
        let vectors = try JSONDecoder().decode(CryptoVectorsFile.self, from: Data(contentsOf: url))
        let crypto = CryptoActor()
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
        return crypto
    }

    private func makeEngine(
        crypto: CryptoActor,
        net: MockNet,
        entities: Entities = .empty()
    ) async throws -> (SyncEngine, CipherStore, EntityStore) {
        let db = try AppDatabase.openInMemory()
        let cipher = CipherStore(dbQueue: db, cipher: ActorRecordCipher(crypto: crypto))
        let store = EntityStore(entities: entities)
        store.onChanges = { changes, source in
            switch source {
            case .local: try? await cipher.applyLocal(changes)
            case .sync: try? await cipher.applyRemote(changes)
            }
        }
        let engine = SyncEngine(store: store, db: cipher, crypto: crypto, net: net)
        return (engine, cipher, store)
    }

    @Test func resyncOn410ClearsCursorAndRepulls() async throws {
        let crypto = try await unlockCrypto()
        let net = MockNet()
        net.pullPages = [
            .failure(APIError.http(status: 410, code: "resync", message: "stale")),
            .success(PullResponse(records: [], cursor: 42, hasMore: false)),
        ]
        let (engine, cipher, _) = try await makeEngine(crypto: crypto, net: net)
        try await cipher.setCursor(10)
        try await cipher.setUploaded(true)
        try await engine.sync()
        #expect(net.pullCalls >= 2)
        #expect(try await cipher.cursor() == 42)
    }

    @Test func conflictKeepsOutboxAndTriggersAnotherRound() async throws {
        let crypto = try await unlockCrypto()
        let net = MockNet()
        net.pullPages = [
            .success(PullResponse(records: [], cursor: 0, hasMore: false)),
            .success(PullResponse(records: [], cursor: 0, hasMore: false)),
        ]
        var pushCount = 0
        net.pushHandler = { records in
            pushCount += 1
            let id = records[0].id
            if pushCount == 1 {
                return PushResponse(
                    results: [PushResultRow(id: id, seq: 0, conflict: true, error: nil)],
                    head: 1
                )
            }
            return PushResponse(
                results: [PushResultRow(id: id, seq: 5, conflict: false, error: nil)],
                head: 5
            )
        }
        var e = Entities.empty()
        e.todos["t1"] = EntityJSON.decodeTodo([
            "type": "todo", "id": "t1", "title": "X", "notes": "", "status": "open",
            "start": "inbox", "tonight": false, "tagIds": [] as [String], "order": "a0",
            "createdAt": "2026-10-01T09:00:00.000Z", "updatedAt": "2026-10-01T09:00:00.000Z",
        ], id: "t1")
        let (engine, cipher, _) = try await makeEngine(crypto: crypto, net: net, entities: e)
        try await cipher.replaceAll(e)
        try await cipher.markDirty(["todos/t1"])
        try await cipher.setUploaded(true)
        try await engine.sync()
        #expect(pushCount >= 2)
        let pending = try await cipher.pendingKeys()
        #expect(pending.isEmpty)
        #expect(try await cipher.seqs(["todos/t1"])["todos/t1"] == 5)
    }

    @Test func unknownAlgIsHeldAndSetsNeedsUpdate() async throws {
        let crypto = try await unlockCrypto()
        let net = MockNet()
        net.pullPages = [
            .success(
                PullResponse(
                    records: [
                        WireRecord(
                            id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                            seq: 9,
                            alg: 99,
                            keyId: 1,
                            nonce: Base64Std.encode([UInt8](repeating: 1, count: 24)),
                            ciphertext: Base64Std.encode([UInt8](repeating: 2, count: 32)),
                            tombstone: nil
                        ),
                    ],
                    cursor: 9,
                    hasMore: false
                )
            ),
        ]
        let (engine, cipher, _) = try await makeEngine(crypto: crypto, net: net)
        try await cipher.setUploaded(true)
        try await engine.sync()
        #expect(engine.sawUnknownAlg)
        #expect(try await cipher.needsUpgrade())
        #expect(try await cipher.opaqueCount() == 1)
        #expect(try await cipher.isEmpty()) // no plaintext merge
    }

    @Test func fullPullPrunesUnseenLocalEntities() async throws {
        let crypto = try await unlockCrypto()
        let net = MockNet()
        net.pullPages = [
            .success(PullResponse(records: [], cursor: 1, hasMore: false)),
        ]
        var e = Entities.empty()
        e.todos["t1"] = sampleTodo(id: "t1", title: "Local")
        let (engine, cipher, store) = try await makeEngine(crypto: crypto, net: net, entities: e)
        try await cipher.replaceAll(e)
        try await cipher.setUploaded(true)
        try await engine.sync()
        #expect(store.entities.todos["t1"] == nil)
    }

    @Test func unknownAlgFullPullDoesNotPruneLocalEntities() async throws {
        let crypto = try await unlockCrypto()
        let net = MockNet()
        net.pullPages = [
            .success(
                PullResponse(
                    records: [
                        WireRecord(
                            id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                            seq: 9,
                            alg: 99,
                            keyId: 1,
                            nonce: Base64Std.encode([UInt8](repeating: 1, count: 24)),
                            ciphertext: Base64Std.encode([UInt8](repeating: 2, count: 32)),
                            tombstone: nil
                        ),
                    ],
                    cursor: 9,
                    hasMore: false
                )
            ),
        ]
        var e = Entities.empty()
        e.todos["t1"] = sampleTodo(id: "t1", title: "Keep me")
        let (engine, cipher, store) = try await makeEngine(crypto: crypto, net: net, entities: e)
        try await cipher.replaceAll(e)
        try await cipher.setUploaded(true)
        try await engine.sync()
        #expect(engine.sawUnknownAlg)
        #expect(try await cipher.needsUpgrade())
        #expect(store.entities.todos["t1"]?.title == "Keep me")
    }

    private func sampleTodo(id: String, title: String) -> Todo {
        EntityJSON.decodeTodo([
            "type": "todo", "id": id, "title": title, "notes": "", "status": "open",
            "start": "inbox", "tonight": false, "tagIds": [] as [String], "order": "a0",
            "createdAt": "2026-10-01T09:00:00.000Z", "updatedAt": "2026-10-01T09:00:00.000Z",
        ], id: id)
    }
}

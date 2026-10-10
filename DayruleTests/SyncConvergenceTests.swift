import Foundation
import Testing
@testable import Dayrule

/// Two-device FakeServer sync (port of `web/src/sync/engine.test.ts` convergence cases).
@Suite("Sync convergence")
@MainActor
struct SyncConvergenceTests {
    /// In-memory server sync semantics (`server/internal/store/records.go`).
    private final class FakeServer: SyncTransport, @unchecked Sendable {
        struct Stored {
            var id: String
            var seq: Int64
            var alg: Int
            var keyId: Int
            var nonce: String
            var ciphertext: String
            var tombstone: Bool?
        }

        var records: [String: Stored] = [:]
        var next: Int64 = 1
        var floor: Int64 = 0
        var offline = false
        var quotaFull = false

        private func check() throws {
            if offline { throw APIError.offline }
        }

        func pull(since: Int64, full: Bool) async throws -> PullResponse {
            try check()
            if since > 0, since < floor, !full {
                throw APIError.http(status: 410, code: "resync", message: "resync")
            }
            let all = records.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
            let page = Array(all.prefix(2))
            return PullResponse(
                records: page.map {
                    WireRecord(
                        id: $0.id, seq: $0.seq, alg: $0.alg, keyId: $0.keyId,
                        nonce: $0.nonce, ciphertext: $0.ciphertext, tombstone: $0.tombstone
                    )
                },
                cursor: page.last?.seq ?? since,
                hasMore: all.count > page.count
            )
        }

        func push(_ wire: [PushWireRecord]) async throws -> PushResponse {
            try check()
            var results: [PushResultRow] = []
            for r in wire {
                let cur = records[r.id]
                if (cur?.seq ?? 0) != r.baseSeq {
                    results.append(PushResultRow(id: r.id, seq: cur?.seq ?? 0, conflict: true, error: nil))
                    continue
                }
                if quotaFull, r.tombstone != true {
                    results.append(PushResultRow(id: r.id, seq: cur?.seq ?? 0, conflict: nil, error: "quota"))
                    continue
                }
                let seq = next
                next += 1
                records[r.id] = Stored(
                    id: r.id, seq: seq, alg: r.alg, keyId: r.keyId,
                    nonce: r.nonce, ciphertext: r.ciphertext, tombstone: r.tombstone
                )
                results.append(PushResultRow(id: r.id, seq: seq, conflict: nil, error: nil))
            }
            return PushResponse(results: results, head: next - 1)
        }
    }

    private final class Wall: @unchecked Sendable {
        var ms: Int
        private var idSeq = 0
        init(_ ms: Int) { self.ms = ms }
        func bump(_ by: Int = 1000) -> Int {
            ms += by
            return ms
        }
        func nextId(prefix: String) -> String {
            idSeq += 1
            return "\(prefix)-\(idSeq)"
        }
    }

    private struct Device {
        var store: EntityStore
        var engine: SyncEngine
        var cipher: CipherStore
        var me: Int
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

    private func device(
        server: FakeServer,
        wall: Wall,
        me: Int,
        crypto: CryptoActor
    ) async throws -> Device {
        let db = try AppDatabase.openInMemory()
        let cipher = CipherStore(dbQueue: db, cipher: ActorRecordCipher(crypto: crypto))
        let clock = StoreClock(
            now: { Date(timeIntervalSince1970: TimeInterval(wall.bump()) / 1000) },
            newId: { wall.nextId(prefix: "d\(me)") },
            hlc: HLC(device: "dev\(me)") { wall.bump(1) }
        )
        let store = EntityStore(clock: clock)
        store.onChanges = { changes, source in
            switch source {
            case .local: try? await cipher.applyLocal(changes)
            case .sync: try? await cipher.applyRemote(changes)
            }
        }
        let engine = SyncEngine(store: store, db: cipher, crypto: crypto, net: server)
        return Device(store: store, engine: engine, cipher: cipher, me: me)
    }

    private func add(_ d: Device, _ title: String) throws -> Todo {
        try d.store.run("add") { dr, env in
            try Commands.createTodo(dr, env, .init(title: title, placement: .inbox))
        }
    }

    private func titles(_ d: Device) -> [String] {
        d.store.entities.todos.values.map(\.title).sorted()
    }

    private func sync(_ d: Device) async throws {
        await d.store.awaitPendingPersist()
        try await d.engine.sync()
        await d.store.awaitPendingPersist()
    }

    @Test func syncsCreatesEditsAndDeletesBetweenTwoDevices() async throws {
        let server = FakeServer()
        let wall = Wall(1_700_000_000_000)
        // Same AK on both devices (shared vectors wrap).
        let cryptoA = try await unlockCrypto()
        let cryptoB = try await unlockCrypto()
        let a = try await device(server: server, wall: wall, me: 1, crypto: cryptoA)
        let b = try await device(server: server, wall: wall, me: 2, crypto: cryptoB)

        let t1 = try add(a, "one")
        _ = try add(a, "two")
        _ = try add(a, "three")
        try await sync(a)
        try await sync(b)
        #expect(titles(b) == ["one", "three", "two"])

        try b.store.run("edit") { d, env in
            Commands.updateTodo(d, env, id: t1.id, title: nil, notes: "from b")
        }
        try a.store.run("edit") { d, env in
            Commands.updateTodo(d, env, id: t1.id, title: "ONE", notes: nil)
        }
        try await sync(b)
        try await sync(a)
        try await sync(b)
        #expect(a.store.entities.todos[t1.id]?.title == "ONE")
        #expect(a.store.entities.todos[t1.id]?.notes == "from b")
        #expect(b.store.entities.todos[t1.id]?.title == "ONE")
        #expect(b.store.entities.todos[t1.id]?.notes == "from b")

        try a.store.run("delete") { d, _ in
            d.remove(.todos, id: t1.id)
        }
        try await sync(a)
        try await sync(b)
        #expect(titles(b) == ["three", "two"])
    }

    @Test func convergesAfterBothDevicesEditOffline() async throws {
        let server = FakeServer()
        let wall = Wall(1_700_000_000_000)
        let cryptoA = try await unlockCrypto()
        let cryptoB = try await unlockCrypto()
        let a = try await device(server: server, wall: wall, me: 1, crypto: cryptoA)
        let b = try await device(server: server, wall: wall, me: 2, crypto: cryptoB)

        let shared = try add(a, "shared")
        try await sync(a)
        try await sync(b)

        server.offline = true
        _ = try add(a, "a only")
        _ = try add(b, "b only")
        try a.store.run("x") { d, env in
            Commands.updateTodo(d, env, id: shared.id, title: "by a", notes: nil)
        }
        try b.store.run("x") { d, env in
            Commands.updateTodo(d, env, id: shared.id, title: "by b", notes: nil)
        }
        await #expect(throws: APIError.self) {
            try await sync(a)
        }
        server.offline = false

        try await sync(a)
        try await sync(b)
        try await sync(a)
        #expect(titles(a) == ["a only", "b only", "by b"])
        #expect(a.store.entities == b.store.entities)
    }

    @Test func editAfterDeletionRevivesRecord() async throws {
        let server = FakeServer()
        let wall = Wall(1_700_000_000_000)
        let cryptoA = try await unlockCrypto()
        let cryptoB = try await unlockCrypto()
        let a = try await device(server: server, wall: wall, me: 1, crypto: cryptoA)
        let b = try await device(server: server, wall: wall, me: 2, crypto: cryptoB)

        let t = try add(a, "x")
        try await sync(a)
        try await sync(b)

        try a.store.run("del") { d, _ in
            d.remove(.todos, id: t.id)
        }
        try b.store.run("edit") { d, env in
            Commands.updateTodo(d, env, id: t.id, title: nil, notes: "later edit")
        }
        try await sync(a)
        try await sync(b)
        try await sync(a)
        #expect(a.store.entities.todos[t.id]?.notes == "later edit")
        #expect(b.store.entities.todos[t.id]?.notes == "later edit")
    }
}

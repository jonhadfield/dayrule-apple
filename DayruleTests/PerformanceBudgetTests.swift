import Foundation
import Testing
@testable import Dayrule

/// Soft CI ceilings for hot paths in PLAN §14.3 (unlock KDF, list selectors,
/// cold vault decrypt after unlock). Ceilings are generous so Apple Silicon
/// vs CI variance does not flake; tighten after a few green baseline runs.
@Suite("Performance budgets")
struct PerformanceBudgetTests {
    /// Default KDF is ops=3 / 64 MiB. Local Apple Silicon is typically well
    /// under 2s; CI runners vary — 8s leaves headroom without hiding a 10×
    /// regression.
    private static let argon2Ceiling: Duration = .seconds(8)
    /// inbox + browseTree + scheduled over ~1k entities. Soft ceiling for CI.
    private static let listSelectorsCeiling: Duration = .milliseconds(100)
    /// Decrypt ~200 sync-shaped records with a known AK (post-unlock hydrate).
    /// Local Apple Silicon is usually well under 100ms; 2s covers CI variance.
    private static let vaultDecryptCeiling: Duration = .seconds(2)
    private static let vaultDecryptCount = 200

    @Test("Argon2id default KDF stays under unlock budget")
    func argon2DefaultKdfBudget() throws {
        Primitives.ready()
        let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
        let password = "performance-budget-password-ok"

        // Warm sodium / page-in once so the timed call is representative of
        // a subsequent unlock, not cold process start.
        _ = try Primitives.deriveMasterKey(
            password: password,
            salt: salt,
            kdf: .default
        )

        let clock = ContinuousClock()
        let started = clock.now
        let key = try Primitives.deriveMasterKey(
            password: password,
            salt: salt,
            kdf: .default
        )
        let elapsed = clock.now - started
        #expect(key.count == CryptoConstants.keyBytes)
        #expect(
            elapsed < Self.argon2Ceiling,
            "Argon2id default KDF took \(elapsed); budget is \(Self.argon2Ceiling)"
        )
    }

    @Test("List selectors stay under budget on a ~1k-entity vault")
    func listSelectorsBudget() {
        let world = World()
        let areas = (0..<10).map { world.area(title: "Area \($0)") }
        for (i, area) in areas.enumerated() {
            for j in 0..<5 {
                _ = world.project(title: "P \(i)-\(j)", areaId: area.id, start: .ready)
            }
        }
        // Mix buckets so inbox / today / scheduled / browse all do real work.
        let today = When.toLocalDate(Date())
        for i in 0..<700 {
            _ = world.todo(title: "Inbox \(i)", start: .inbox)
        }
        for i in 0..<150 {
            _ = world.todo(
                title: "Today \(i)",
                start: .ready,
                startDate: today,
                todayOrder: String(format: "a%04d", i)
            )
        }
        for i in 0..<150 {
            let offset = (i % 30) + 1
            let day = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
            _ = world.todo(
                title: "Scheduled \(i)",
                start: .ready,
                startDate: When.toLocalDate(day)
            )
        }
        #expect(world.e.todos.count == 1000)
        #expect(world.e.projects.count == 50)

        let ctx = Lists.Context(today: today, keepVisible: [])
        let clock = ContinuousClock()
        let started = clock.now
        let inbox = Lists.inbox(world.e, ctx)
        let tree = Lists.browseTree(world.e)
        let scheduled = Lists.scheduled(world.e, ctx)
        let elapsed = clock.now - started

        #expect(inbox.count == 700)
        #expect(tree.areaGroups.count == 10)
        #expect(!scheduled.days.isEmpty || !scheduled.months.isEmpty)
        #expect(
            elapsed < Self.listSelectorsCeiling,
            "List selectors took \(elapsed); budget is \(Self.listSelectorsCeiling)"
        )
    }

    /// Cold vault hydrate after unlock: decrypt many sync-shaped envelopes
    /// with a known account key (Argon2 is budgeted separately above).
    @Test("Cold vault decrypt of ~200 sync records stays under budget")
    func coldVaultDecryptBudget() throws {
        Primitives.ready()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/shared/crypto-vectors.json")
        let vectors = try JSONDecoder().decode(CryptoVectorsFile.self, from: Data(contentsOf: url))
        let ak = try Hex.decode(vectors.input.accountKey)
        let userId = vectors.input.userId
        let baseNonce = try Hex.decode(vectors.input.recordNonce)
        #expect(baseNonce.count >= 8)

        var envelopes: [(meta: Primitives.RecordMeta, env: Primitives.Envelope)] = []
        envelopes.reserveCapacity(Self.vaultDecryptCount)
        for i in 0..<Self.vaultDecryptCount {
            let recordId = "sync/budget-\(i)"
            let meta = Primitives.RecordMeta(
                userId: userId,
                recordId: recordId,
                schemaVersion: 1,
                keyId: 1
            )
            var nonce = baseNonce
            // Unique nonce per record without needing a CSPRNG in the timed path.
            let tag = UInt32(i).bigEndian
            withUnsafeBytes(of: tag) { bytes in
                for (offset, byte) in bytes.enumerated() {
                    nonce[nonce.count - 4 + offset] ^= byte
                }
            }
            let payload: [String: Any] = [
                "k": "todos/budget-\(i)",
                "v": [
                    "type": "todo",
                    "title": "Budget \(i)",
                    "notes": "",
                    "tonight": false,
                ] as [String: Any],
            ]
            let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let env = try Primitives.encryptRecordJSON(
                ak: ak,
                meta: meta,
                jsonUTF8: [UInt8](json),
                nonce: nonce
            )
            envelopes.append((meta, env))
        }

        // Warm sodium / page-in once (same pattern as Argon2 budget).
        _ = try Primitives.decryptRecordJSON(
            ak: ak,
            meta: envelopes[0].meta,
            env: envelopes[0].env
        )

        let clock = ContinuousClock()
        let started = clock.now
        for item in envelopes {
            let plain = try Primitives.decryptRecordJSON(
                ak: ak,
                meta: item.meta,
                env: item.env
            )
            #expect(!plain.isEmpty)
        }
        let elapsed = clock.now - started
        #expect(
            elapsed < Self.vaultDecryptCeiling,
            "Cold vault decrypt took \(elapsed); budget is \(Self.vaultDecryptCeiling)"
        )
    }
}

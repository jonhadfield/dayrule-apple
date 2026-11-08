import Foundation
import Testing
@testable import Dayrule

/// Soft CI ceilings for hot paths deferred in PLAN §14.3 (unlock) and list
/// render selectors. Ceilings are generous so Apple Silicon vs CI variance
/// does not flake; tighten after a few green baseline runs.
@Suite("Performance budgets")
struct PerformanceBudgetTests {
    /// Default KDF is ops=3 / 64 MiB. Local Apple Silicon is typically well
    /// under 2s; CI runners vary — 8s leaves headroom without hiding a 10×
    /// regression.
    private static let argon2Ceiling: Duration = .seconds(8)
    /// inbox + browseTree + scheduled over ~1k entities. Soft ceiling for CI.
    private static let listSelectorsCeiling: Duration = .milliseconds(100)

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
}

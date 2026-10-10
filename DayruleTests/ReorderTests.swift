import Foundation
import Testing
@testable import Dayrule

@Suite("Commands.reorder")
@MainActor
struct ReorderTests {
    private func fixedClock(ms: Int = 1_700_000_000_000) -> StoreClock {
        final class Counter: @unchecked Sendable {
            var n = 0
            func next() -> String {
                n += 1
                return String(format: "id-%04d", n)
            }
        }
        let counter = Counter()
        return StoreClock(
            now: { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) },
            newId: { counter.next() },
            hlc: HLC(device: "testdevice1") { ms }
        )
    }

    @Test func reordersByRewritingOnlyMovedItem() throws {
        let store = EntityStore(clock: fixedClock())
        let a = try store.run("new") { d, env in
            try Commands.createTodo(d, env, .init(title: "a", placement: .inbox))
        }
        let b = try store.run("new") { d, env in
            try Commands.createTodo(d, env, .init(title: "b", placement: .inbox))
        }
        let c = try store.run("new") { d, env in
            try Commands.createTodo(d, env, .init(title: "c", placement: .inbox))
        }
        let beforeA = store.entities.todos[a.id]
        let beforeB = store.entities.todos[b.id]

        try store.run("reorder") { d, env in
            try Commands.reorder(
                d,
                env,
                collection: .todos,
                id: c.id,
                field: .order,
                before: a.id,
                after: b.id
            )
        }

        let ctx = Lists.Context(today: When.toLocalDate(Date(timeIntervalSince1970: 1_700_000_000)), keepVisible: nil)
        #expect(Lists.inbox(store.entities, ctx).map(\.title) == ["a", "c", "b"])
        #expect(store.entities.todos[a.id] == beforeA)
        #expect(store.entities.todos[b.id] == beforeB)
        #expect(store.entities.todos[c.id]?.order != c.order)
    }
}

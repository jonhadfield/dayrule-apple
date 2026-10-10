import Testing
@testable import Dayrule

@Suite("VaultToEntities")
struct VaultToEntitiesTests {
    @Test func buildsInboxTodosFromVaultTitles() {
        let vault = VaultSnapshot(
            entities: [
                VaultEntity(key: "todos/a", title: "Buy milk", type: "todo"),
                VaultEntity(key: "projects/p1", title: "Home", type: "project"),
                VaultEntity(key: "areas/ar1", title: "Life", type: "area"),
                VaultEntity(key: "tags/t1", title: "ignored", type: "tag"),
            ],
            counts: [:],
            recordCount: 4,
            skippedUnknownAlg: 0
        )
        let e = VaultToEntities.build(from: vault)
        #expect(e.todos.count == 1)
        #expect(e.todos["a"]?.title == "Buy milk")
        #expect(e.todos["a"]?.start == .inbox)
        #expect(e.projects["p1"]?.title == "Home")
        #expect(e.areas["ar1"]?.title == "Life")
        #expect(e.tags.isEmpty)

        let ctx = Lists.Context(today: "2026-10-10", keepVisible: nil)
        #expect(Lists.inbox(e, ctx).map(\.title) == ["Buy milk"])
    }
}

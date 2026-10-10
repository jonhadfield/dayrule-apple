import Testing
@testable import Dayrule

@Suite("VaultToEntities")
struct VaultToEntitiesTests {
    @Test func buildsInboxTodosFromVaultTitles() {
        let vault = VaultSnapshot(
            entities: [
                VaultEntity(key: "todos/a", title: "Buy milk", type: "todo"),
            ],
            payloads: [
                SyncPayload(
                    key: "todos/a",
                    value: JSONDict.fromAny([
                        "type": "todo",
                        "title": "Buy milk",
                        "notes": "",
                        "status": "open",
                        "start": "inbox",
                        "tonight": false,
                        "tagIds": [] as [String],
                        "order": "a0",
                    ]),
                    deleted: nil
                ),
                SyncPayload(
                    key: "projects/p1",
                    value: JSONDict.fromAny([
                        "type": "project",
                        "title": "Home",
                        "notes": "",
                        "status": "open",
                        "start": "ready",
                        "tonight": false,
                        "tagIds": [] as [String],
                        "order": "a0",
                    ]),
                    deleted: nil
                ),
                SyncPayload(
                    key: "areas/ar1",
                    value: JSONDict.fromAny([
                        "type": "area",
                        "title": "Life",
                        "order": "a0",
                        "tagIds": [] as [String],
                    ]),
                    deleted: nil
                ),
                SyncPayload(
                    key: "tags/t1",
                    value: JSONDict.fromAny([
                        "type": "tag",
                        "title": "kept",
                        "order": "a0",
                    ]),
                    deleted: nil
                ),
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
        #expect(e.tags["t1"]?.title == "kept")

        let ctx = Lists.Context(today: "2026-10-10", keepVisible: nil)
        #expect(Lists.inbox(e, ctx).map(\.title) == ["Buy milk"])
    }
}

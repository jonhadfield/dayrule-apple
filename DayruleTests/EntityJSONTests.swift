import Foundation
import Testing
@testable import Dayrule

@Suite("EntityJSON")
struct EntityJSONTests {
    @Test func preservesUnknownFieldsAndClocksOnRoundTrip() {
        let raw: [String: Any] = [
            "type": "todo",
            "id": "t1",
            "createdAt": "2026-10-01T09:00:00.000Z",
            "updatedAt": "2026-10-01T09:00:00.000Z",
            "title": "Buy milk",
            "notes": "semi",
            "status": "open",
            "start": "inbox",
            "tonight": false,
            "tagIds": ["tag-1"],
            "order": "a0",
            "clock": [
                "title": "k00000001-0001-dev1",
                "futureField": "k00000002-0001-dev1",
            ],
            "futureField": "keep-me",
            "nestedExtra": ["a": 1] as [String: Any],
        ]
        let todo = EntityJSON.decodeTodo(raw, id: "t1")
        #expect(todo.title == "Buy milk")
        #expect(todo.unknown["futureField"]?.stringValue == "keep-me")
        #expect(todo.unknown["nestedExtra"] != nil)
        #expect(todo.clock?["futureField"] == "k00000002-0001-dev1")

        let encoded = EntityJSON.encode(todo)
        #expect(encoded["futureField"] as? String == "keep-me")
        #expect((encoded["nestedExtra"] as? [String: Any])?["a"] as? Int == 1)
        #expect((encoded["clock"] as? [String: String])?["futureField"] == "k00000002-0001-dev1")
        #expect(encoded["title"] as? String == "Buy milk")
        #expect(encoded["type"] as? String == "todo")
    }

    @Test func insertBuildsEntitiesFromVaultPayloads() {
        let vault = VaultSnapshot(
            entities: [],
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
                        "extra": true,
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
            ],
            counts: [:],
            recordCount: 2,
            skippedUnknownAlg: 0
        )
        let e = VaultToEntities.build(from: vault)
        #expect(e.todos["a"]?.title == "Buy milk")
        #expect(e.todos["a"]?.unknown["extra"] == .bool(true))
        #expect(e.projects["p1"]?.title == "Home")
        let ctx = Lists.Context(today: "2026-10-10", keepVisible: nil)
        #expect(Lists.inbox(e, ctx).map(\.title) == ["Buy milk"])
    }
}

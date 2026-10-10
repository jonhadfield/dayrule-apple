import Testing
@testable import Dayrule

@Suite("Incoming")
struct IncomingTests {
    @Test func mergesRemoteFieldAndPushBackWhenLocalWinsOtherField() {
        let local: [String: Any] = [
            "type": "todo",
            "id": "t1",
            "title": "Local",
            "notes": "old",
            "clock": ["title": "k00000002-0001-dev1", "notes": "k00000001-0001-dev1"],
        ]
        let remote: [String: Any] = [
            "type": "todo",
            "id": "t1",
            "title": "Remote",
            "notes": "new",
            "clock": ["title": "k00000001-0001-dev1", "notes": "k00000003-0001-dev1"],
        ]
        var e = Entities.empty()
        e.todos["t1"] = EntityJSON.decodeTodo(local, id: "t1")
        let result = Incoming.incomingChanges(
            entities: e,
            items: [.init(key: "todos/t1", value: remote, deleted: nil)]
        )
        #expect(result.changes.count == 1)
        #expect(result.pushBack == ["todos/t1"])
        if case let .entity(_, _, _, after?, _) = result.changes[0] {
            #expect(after["title"]?.stringValue == "Local")
            #expect(after["notes"]?.stringValue == "new")
        } else {
            Issue.record("expected entity change")
        }
    }

    @Test func allKeysIncludesSettingsAndTodos() {
        var e = Entities.empty()
        e.todos["a"] = EntityJSON.decodeTodo([
            "type": "todo", "id": "a", "title": "A", "notes": "", "status": "open",
            "start": "inbox", "tonight": false, "tagIds": [] as [String], "order": "a0",
            "createdAt": "2026-10-01T09:00:00.000Z", "updatedAt": "2026-10-01T09:00:00.000Z",
        ], id: "a")
        let keys = Incoming.allKeys(e)
        #expect(keys.contains(CipherStore.settingsKey))
        #expect(keys.contains("todos/a"))
    }
}

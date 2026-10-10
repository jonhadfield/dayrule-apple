import Foundation
import Testing
@testable import Dayrule

@Suite("EntityStore")
@MainActor
struct StoreTests {
    private func fixedClock(ms: Int = 1_700_000_000_000) -> StoreClock {
        StoreClock(
            now: { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) },
            newId: { "id-fixed-0001" },
            hlc: HLC(device: "testdevice1") { ms }
        )
    }

    @Test func createTodoStampsClockAndUndoRestores() throws {
        let store = EntityStore(clock: fixedClock())
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Milk", placement: .inbox))
        }
        #expect(store.entities.todos[todo.id]?.title == "Milk")
        #expect(store.entities.todos[todo.id]?.start == .inbox)
        #expect(store.entities.todos[todo.id]?.clock?["title"] != nil)
        #expect(store.canUndo)

        _ = store.undo()
        #expect(store.entities.todos[todo.id] == nil)
        #expect(store.canRedo)

        _ = store.redo()
        #expect(store.entities.todos[todo.id]?.title == "Milk")
    }

    @Test func setWhenCompleteAndTrash() throws {
        let store = EntityStore(clock: fixedClock())
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Task", placement: .inbox))
        }
        try store.run("When") { d, env in
            try Commands.setWhen(d, env, ids: [todo.id], when: .today)
        }
        #expect(store.entities.todos[todo.id]?.startDate != nil)

        store.run("Complete") { d, env in
            Commands.setStatus(d, env, ids: [todo.id], status: .completed)
        }
        #expect(store.entities.todos[todo.id]?.status == .completed)
        #expect(store.entities.todos[todo.id]?.completedAt != nil)

        _ = store.undo()
        #expect(store.entities.todos[todo.id]?.status == .open)

        store.run("Trash") { d, env in
            Commands.trashItems(d, env, ids: [todo.id])
        }
        #expect(store.entities.todos[todo.id]?.trashedAt != nil)
    }

    @Test func hydrateClearsUndoStacks() throws {
        let store = EntityStore(clock: fixedClock())
        _ = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "X", placement: .inbox))
        }
        store.hydrate(.empty())
        #expect(store.entities.todos.isEmpty)
        #expect(!store.canUndo)
    }

    @Test func unknownFieldsSurviveEdit() throws {
        var e = Entities.empty()
        e.todos["t1"] = EntityJSON.decodeTodo([
            "type": "todo",
            "id": "t1",
            "createdAt": "2026-10-01T09:00:00.000Z",
            "updatedAt": "2026-10-01T09:00:00.000Z",
            "title": "Keep",
            "notes": "",
            "status": "open",
            "start": "inbox",
            "tonight": false,
            "tagIds": [] as [String],
            "order": "a0",
            "futureField": "keep-me",
        ], id: "t1")
        let store = EntityStore(entities: e, clock: fixedClock())
        store.run("Rename") { d, env in
            Commands.updateTodo(d, env, id: "t1", title: "Kept", notes: nil)
        }
        #expect(store.entities.todos["t1"]?.title == "Kept")
        #expect(store.entities.todos["t1"]?.unknown["futureField"]?.stringValue == "keep-me")
        #expect(store.entities.todos["t1"]?.clock?["title"] != nil)
        #expect(store.entities.todos["t1"]?.clock?["futureField"] == nil)
    }
}

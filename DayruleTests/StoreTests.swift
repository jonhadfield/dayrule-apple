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

    @Test func createProjectUpdateAndEmptyTrash() throws {
        final class Seq: @unchecked Sendable {
            private var n = 0
            func next() -> String {
                n += 1
                return String(format: "id-%04d", n)
            }
        }
        let seq = Seq()
        let clock = StoreClock(
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            newId: { seq.next() },
            hlc: HLC(device: "testdevice1") { 1_700_000_000_000 }
        )
        let store = EntityStore(clock: clock)
        let project = try store.run("Project") { d, env in
            try Commands.createProject(d, env, title: "Ship", areaId: nil)
        }
        #expect(store.entities.projects[project.id]?.title == "Ship")
        #expect(store.entities.projects[project.id]?.start == .ready)

        store.run("Rename project") { d, env in
            Commands.updateProject(d, env, id: project.id, title: "Shipped", notes: "done notes")
        }
        #expect(store.entities.projects[project.id]?.title == "Shipped")
        #expect(store.entities.projects[project.id]?.notes == "done notes")

        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Nested", placement: .project(projectId: project.id, headingId: nil)))
        }
        #expect(todo.id != project.id)
        store.run("Trash project") { d, env in
            Commands.trashItems(d, env, ids: [project.id])
        }
        #expect(store.entities.projects[project.id]?.trashedAt != nil)

        // emptyTrash also removes children of trashed areas/projects even if
        // the child itself was not soft-trashed (web behaviour).
        store.run("Empty Trash") { d, _ in
            Commands.emptyTrash(d)
        }
        #expect(store.entities.projects[project.id] == nil)
        #expect(store.entities.todos[todo.id] == nil)
    }

    @Test func emptyTrashRemovesSoftTrashedTodo() throws {
        let store = EntityStore(clock: fixedClock())
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Gone", placement: .inbox))
        }
        store.run("Trash") { d, env in
            Commands.trashItems(d, env, ids: [todo.id])
        }
        store.run("Empty Trash") { d, _ in
            Commands.emptyTrash(d)
        }
        #expect(store.entities.todos[todo.id] == nil)
    }

    @Test func setDeadlineAndClear() throws {
        let store = EntityStore(clock: fixedClock())
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Due soon", placement: .inbox))
        }
        store.run("Deadline") { d, env in
            Commands.setDeadline(d, env, ids: [todo.id], deadline: "2026-10-20")
        }
        #expect(store.entities.todos[todo.id]?.deadline == "2026-10-20")
        store.run("Clear deadline") { d, env in
            Commands.setDeadline(d, env, ids: [todo.id], deadline: nil)
        }
        #expect(store.entities.todos[todo.id]?.deadline == nil)
    }

    @Test func tagsHeadingsAndLogCompleted() throws {
        final class Seq: @unchecked Sendable {
            private var n = 0
            func next() -> String {
                n += 1
                return String(format: "id-%04d", n)
            }
        }
        let seq = Seq()
        let clock = StoreClock(
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            newId: { seq.next() },
            hlc: HLC(device: "testdevice1") { 1_700_000_000_000 }
        )
        let store = EntityStore(clock: clock)
        let project = try store.run("Project") { d, env in
            try Commands.createProject(d, env, title: "Build")
        }
        let heading = try store.run("Heading") { d, env in
            try Commands.createHeading(d, env, projectId: project.id, title: "Materials")
        }
        #expect(store.entities.headings[heading.id]?.title == "Materials")
        let tag = try store.run("Tag") { d, env in
            try Commands.createTag(d, env, title: "Errand")
        }
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(
                d, env, .init(title: "Buy screws", placement: .project(projectId: project.id, headingId: heading.id))
            )
        }
        store.run("Tags") { d, env in
            Commands.setTags(d, env, ids: [todo.id], tagIds: [tag.id])
        }
        #expect(store.entities.todos[todo.id]?.tagIds == [tag.id])

        store.run("Done mode") { d, _ in
            Commands.setDoneMode(d, mode: .manually)
        }
        #expect(store.entities.settings.moveToDone == .manually)
        store.run("Complete") { d, env in
            Commands.setStatus(d, env, ids: [todo.id], status: .completed)
        }
        let ctx = Lists.Context(today: "2023-11-14", keepVisible: nil)
        #expect(!Lists.isInDone(store.entities, .todo(store.entities.todos[todo.id]!), ctx))
        store.run("Move to Done") { d, env in
            Commands.moveToDoneNow(d, env)
        }
        #expect(store.entities.settings.lastMovedToDoneAt != nil)
        #expect(Lists.isInDone(store.entities, .todo(store.entities.todos[todo.id]!), ctx))
    }
}

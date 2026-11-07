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

    /// Unique ids so New List can create an area and a nested project in one store.
    private func sequentialStore() -> EntityStore {
        final class Seq: @unchecked Sendable {
            private var n = 0
            func next() -> String {
                n += 1
                return String(format: "id-%04d", n)
            }
        }
        let seq = Seq()
        return EntityStore(clock: StoreClock(
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            newId: { seq.next() },
            hlc: HLC(device: "testdevice1") { 1_700_000_000_000 }
        ))
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

    @Test func checklistAddUpdateRemove() throws {
        let store = EntityStore(clock: fixedClock())
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Shop", placement: .inbox))
        }
        let item = try store.run("Checklist") { d, env in
            try Commands.addChecklistItem(d, env, todoId: todo.id, title: "Milk")
        }
        #expect(store.entities.checklistItems[item.id]?.title == "Milk")
        #expect(store.entities.checklistItems[item.id]?.done == false)

        store.run("Checklist") { d, env in
            Commands.updateChecklistItem(d, env, id: item.id, done: true)
        }
        #expect(store.entities.checklistItems[item.id]?.done == true)

        store.run("Checklist") { d, env in
            Commands.updateChecklistItem(d, env, id: item.id, title: "Oat milk")
        }
        #expect(store.entities.checklistItems[item.id]?.title == "Oat milk")

        store.run("Checklist") { d, _ in
            Commands.removeChecklistItem(d, id: item.id)
        }
        #expect(store.entities.checklistItems[item.id] == nil)
    }

    @Test func convertTodoToProjectWithChecklistChildren() throws {
        let store = sequentialStore()
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(
                d, env,
                .init(title: "Pack", placement: .today)
            )
        }
        _ = try store.run("Checklist") { d, env in
            try Commands.addChecklistItem(d, env, todoId: todo.id, title: "socks")
        }
        let passport = try store.run("Checklist") { d, env in
            try Commands.addChecklistItem(d, env, todoId: todo.id, title: "passport")
        }
        store.run("Checklist") { d, env in
            Commands.updateChecklistItem(d, env, id: passport.id, done: true)
        }

        let project = try store.run("Convert to Project") { d, env in
            try Commands.convertTodoToProject(d, env, todoId: todo.id)
        }

        #expect(store.entities.todos[todo.id] == nil)
        #expect(project.title == "Pack")
        let expectedToday = When.toLocalDate(Date(timeIntervalSince1970: 1_700_000_000))
        #expect(project.startDate == expectedToday)
        #expect(project.todayOrder != nil)
        let kids = store.entities.todos.values
            .filter { $0.projectId == project.id }
            .sorted { $0.title < $1.title }
        #expect(kids.map(\.title) == ["passport", "socks"])
        #expect(kids.first { $0.title == "passport" }?.status == .completed)
        #expect(kids.first { $0.title == "socks" }?.status == .open)
        #expect(store.entities.checklistItems.isEmpty)
    }

    @Test func convertHeadingToProjectMovesTodos() throws {
        let store = sequentialStore()
        let area = try store.run("Area") { d, env in
            try Commands.createArea(d, env, title: "Home")
        }
        let parent = try store.run("Project") { d, env in
            try Commands.createProject(d, env, title: "Parent", areaId: area.id)
        }
        let heading = try store.run("Heading") { d, env in
            try Commands.createHeading(d, env, projectId: parent.id, title: "Kitchen")
        }
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(
                d, env,
                .init(
                    title: "Clean",
                    placement: .project(projectId: parent.id, headingId: heading.id)
                )
            )
        }

        let next = try store.run("Convert Heading to Project") { d, env in
            try Commands.convertHeadingToProject(d, env, headingId: heading.id)
        }

        #expect(store.entities.headings[heading.id] == nil)
        #expect(next.title == "Kitchen")
        #expect(next.areaId == area.id)
        #expect(store.entities.todos[todo.id]?.projectId == next.id)
        #expect(store.entities.todos[todo.id]?.headingId == nil)
    }

    @Test func convertProjectToTodoWithChecklistChildren() throws {
        let store = sequentialStore()
        let project = try store.run("Project") { d, env in
            try Commands.createProject(d, env, title: "Trip")
        }
        _ = try store.run("Heading") { d, env in
            try Commands.createHeading(d, env, projectId: project.id, title: "Drop me")
        }
        let book = try store.run("Add") { d, env in
            try Commands.createTodo(
                d, env,
                .init(title: "Book", placement: .project(projectId: project.id, headingId: nil))
            )
        }
        let pack = try store.run("Add") { d, env in
            try Commands.createTodo(
                d, env,
                .init(title: "Pack", placement: .project(projectId: project.id, headingId: nil))
            )
        }
        store.run("Complete") { d, env in
            Commands.setStatus(d, env, ids: [pack.id], status: .completed)
        }

        let todo = try store.run("Convert to To-Do") { d, env in
            try Commands.convertProjectToTodo(d, env, projectId: project.id)
        }

        #expect(store.entities.projects[project.id] == nil)
        #expect(store.entities.todos[book.id] == nil)
        #expect(store.entities.todos[pack.id] == nil)
        #expect(store.entities.headings.isEmpty)
        #expect(todo.title == "Trip")
        let checks = store.entities.checklistItems.values
            .filter { $0.todoId == todo.id }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }
        #expect(checks.count == 2)
        #expect(checks[0].title == "Book")
        #expect(checks[0].done == false)
        #expect(checks[1].title == "Pack")
        #expect(checks[1].done == true)
    }

    @Test func moveTodosToProjectAndInbox() throws {
        final class Seq: @unchecked Sendable {
            private var n = 0
            func next() -> String {
                n += 1
                return String(format: "id-%04d", n)
            }
        }
        let seq = Seq()
        let store = EntityStore(clock: StoreClock(
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            newId: { seq.next() },
            hlc: HLC(device: "testdevice1") { 1_700_000_000_000 }
        ))
        let project = try store.run("Project") { d, env in
            try Commands.createProject(d, env, title: "Renovate")
        }
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Paint", placement: .inbox))
        }
        try store.run("Move") { d, env in
            try Commands.moveTodos(d, env, ids: [todo.id], target: .project(projectId: project.id))
        }
        #expect(store.entities.todos[todo.id]?.projectId == project.id)
        #expect(store.entities.todos[todo.id]?.start == .ready)
        #expect(store.entities.todos[todo.id]?.areaId == nil)

        try store.run("Move") { d, env in
            try Commands.moveTodos(d, env, ids: [todo.id], target: .inbox)
        }
        #expect(store.entities.todos[todo.id]?.projectId == nil)
        #expect(store.entities.todos[todo.id]?.start == .inbox)
    }

    @Test func setWhenInboxAndBacklogVocabulary() throws {
        let store = EntityStore(clock: fixedClock())
        let todo = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Park", placement: .today))
        }
        try store.run("When") { d, env in
            try Commands.setWhen(d, env, ids: [todo.id], when: .ready)
        }
        #expect(store.entities.todos[todo.id]?.start == .ready)
        #expect(store.entities.todos[todo.id]?.startDate == nil)

        try store.run("When") { d, env in
            try Commands.setWhen(d, env, ids: [todo.id], when: .later)
        }
        #expect(store.entities.todos[todo.id]?.start == .later)

        try store.run("When") { d, env in
            try Commands.setWhen(d, env, ids: [todo.id], when: .inbox)
        }
        #expect(store.entities.todos[todo.id]?.start == .inbox)
        #expect(store.entities.todos[todo.id]?.startDate == nil)
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

    @Test func createAreaEmptyTitleRenameAndUndo() throws {
        let store = sequentialStore()
        let area = try store.run("New Area") { d, env in
            try Commands.createArea(d, env, title: "")
        }
        #expect(store.entities.areas[area.id]?.title == "")
        #expect(store.entities.areas[area.id]?.clock?["title"] != nil)
        #expect(Lists.browseTree(store.entities).areaGroups.map(\.area.id) == [area.id])

        store.run("Rename") { d, env in
            Commands.renameArea(d, env, id: area.id, title: "Kitchen")
        }
        #expect(store.entities.areas[area.id]?.title == "Kitchen")

        #expect(store.undo() == "Rename")
        #expect(store.entities.areas[area.id]?.title == "")
        #expect(store.undo() == "New Area")
        #expect(store.entities.areas[area.id] == nil)
        #expect(Lists.browseTree(store.entities).areaGroups.isEmpty)
    }

    @Test func createProjectInAreaIsNestedNotLoose() throws {
        let store = sequentialStore()
        let area = try store.run("New Area") { d, env in
            try Commands.createArea(d, env, title: "")
        }
        let project = try store.run("New Project") { d, env in
            try Commands.createProject(d, env, title: "", areaId: area.id)
        }
        #expect(store.entities.projects[project.id]?.title == "")
        #expect(store.entities.projects[project.id]?.areaId == area.id)
        #expect(store.entities.projects[project.id]?.start == .ready)
        let tree = Lists.browseTree(store.entities)
        #expect(tree.looseProjects.isEmpty)
        #expect(tree.areaGroups.map(\.area.id) == [area.id])
        #expect(tree.areaGroups[0].projects.map(\.id) == [project.id])
    }

    @Test func moveProjectBetweenAreaAndLoose() throws {
        let store = sequentialStore()
        let home = try store.run("Area") { d, env in
            try Commands.createArea(d, env, title: "Home")
        }
        let work = try store.run("Area") { d, env in
            try Commands.createArea(d, env, title: "Work")
        }
        let project = try store.run("Project") { d, env in
            try Commands.createProject(d, env, title: "Kitchen", areaId: home.id)
        }

        try store.run("Move Project") { d, env in
            try Commands.moveProject(d, env, id: project.id, areaId: work.id)
        }
        #expect(store.entities.projects[project.id]?.areaId == work.id)
        var tree = Lists.browseTree(store.entities)
        #expect(tree.looseProjects.isEmpty)
        #expect(tree.areaGroups.first { $0.area.id == work.id }?.projects.map(\.id) == [project.id])
        #expect(tree.areaGroups.first { $0.area.id == home.id }?.projects.isEmpty == true)

        try store.run("Move Project") { d, env in
            try Commands.moveProject(d, env, id: project.id, areaId: nil)
        }
        #expect(store.entities.projects[project.id]?.areaId == nil)
        tree = Lists.browseTree(store.entities)
        #expect(tree.looseProjects.map(\.id) == [project.id])
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

    @Test func setReminderPlainAndOnTemplate() throws {
        #expect(When.roundToQuarter("09:07") == "09:00")
        #expect(When.roundToQuarter("09:08") == "09:15")
        #expect(When.roundToQuarter("23:53") == "23:45")
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
        let plain = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Call", placement: .inbox))
        }
        store.run("Reminder") { d, env in
            Commands.setReminder(d, env, ids: [plain.id], at: "2026-10-10T09:07")
        }
        #expect(store.entities.todos[plain.id]?.reminderAt == "2026-10-10T09:07")
        store.run("Clear Reminder") { d, env in
            Commands.setReminder(d, env, ids: [plain.id], at: nil)
        }
        #expect(store.entities.todos[plain.id]?.reminderAt == nil)

        let template = try store.run("Add") { d, env in
            try Commands.createTodo(d, env, .init(title: "Standup", placement: .today))
        }
        store.run("Repeat") { d, env in
            Repeats.setRepeat(
                d, env, id: template.id,
                rule: RepeatRule(
                    freq: .week, every: 1, weekdays: [0], mode: .fixed,
                    anchor: env.today, next: nil, reminderTime: nil
                )
            )
        }
        store.run("Reminder") { d, env in
            Commands.setReminder(d, env, ids: [template.id], at: "2026-10-10T08:30")
        }
        #expect(store.entities.todos[template.id]?.repeat?.reminderTime == "08:30")
        #expect(store.entities.todos[template.id]?.reminderAt == nil)
    }
}

import Foundation
import Testing
@testable import Dayrule

@Suite("SidebarDrop")
@MainActor
struct SidebarDropTests {
    private func fixedClock(ms: Int = 1_700_000_000_000) -> StoreClock {
        final class Counter: @unchecked Sendable {
            var n = 0
            func next() -> String {
                n += 1
                return String(format: "drop-%04d", n)
            }
        }
        let counter = Counter()
        return StoreClock(
            now: { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) },
            newId: { counter.next() },
            hlc: HLC(device: "testdevice1") { ms }
        )
    }

    @Test("list rows map to move / when / complete / trash")
    func listActions() {
        let today = "2026-11-10"
        #expect(SidebarDrop.action(for: .inbox, today: today) == .move(.inbox))
        #expect(SidebarDrop.action(for: .today, today: today) == .when(.today))
        #expect(SidebarDrop.action(for: .scheduled, today: today) == .when(.date("2026-11-11")))
        #expect(SidebarDrop.action(for: .backlog, today: today) == .move(.none))
        #expect(SidebarDrop.action(for: .notNow, today: today) == .when(.later))
        #expect(SidebarDrop.action(for: .done, today: today) == .complete)
        #expect(SidebarDrop.action(for: .trash, today: today) == .trash)
    }

    @Test("project and area drops move into the container")
    func orgActions() {
        #expect(SidebarDrop.action(projectId: "p1") == .move(.project(projectId: "p1", headingId: nil)))
        #expect(SidebarDrop.action(areaId: "a1") == .move(.area(areaId: "a1")))
    }

    @Test("perform Today sets when via Commands.setWhen")
    func performToday() throws {
        let store = EntityStore(clock: fixedClock())
        let today = When.toLocalDate(Date(timeIntervalSince1970: 1_700_000_000))
        let todo = try store.run("new") { d, env in
            try Commands.createTodo(d, env, .init(title: "Drop me", placement: .inbox))
        }
        let action = SidebarDrop.action(for: .today, today: today)
        try store.run("drop") { d, env in
            try SidebarDrop.perform(action, draft: d, env: env, ids: [todo.id])
        }
        #expect(store.entities.todos[todo.id]?.startDate != nil)
    }

    @Test("perform Done completes; Trash trashes")
    func performDoneAndTrash() throws {
        let store = EntityStore(clock: fixedClock())
        let today = "2026-11-10"
        let a = try store.run("new") { d, env in
            try Commands.createTodo(d, env, .init(title: "A", placement: .inbox))
        }
        let b = try store.run("new") { d, env in
            try Commands.createTodo(d, env, .init(title: "B", placement: .inbox))
        }
        try store.run("drop-done") { d, env in
            try SidebarDrop.perform(
                SidebarDrop.action(for: .done, today: today),
                draft: d,
                env: env,
                ids: [a.id]
            )
        }
        try store.run("drop-trash") { d, env in
            try SidebarDrop.perform(
                SidebarDrop.action(for: .trash, today: today),
                draft: d,
                env: env,
                ids: [b.id]
            )
        }
        #expect(store.entities.todos[a.id]?.status == .completed)
        #expect(store.entities.todos[b.id]?.trashedAt != nil)
    }

    @Test("perform project move nests the to-do")
    func performProjectMove() throws {
        let store = EntityStore(clock: fixedClock())
        let project = try store.run("project") { d, env in
            try Commands.createProject(d, env, title: "Nest")
        }
        let todo = try store.run("new") { d, env in
            try Commands.createTodo(d, env, .init(title: "Into project", placement: .inbox))
        }
        try store.run("drop") { d, env in
            try SidebarDrop.perform(
                SidebarDrop.action(projectId: project.id),
                draft: d,
                env: env,
                ids: [todo.id]
            )
        }
        #expect(store.entities.todos[todo.id]?.projectId == project.id)
    }
}

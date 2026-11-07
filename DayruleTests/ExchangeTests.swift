import Foundation
import Testing
@testable import Dayrule

@Suite("Exchange")
@MainActor
struct ExchangeTests {
    private func store() -> EntityStore {
        final class Seq: @unchecked Sendable {
            private var n = 0
            func next() -> String {
                n += 1
                return String(format: "id-%04d", n)
            }
        }
        let seq = Seq()
        let clock = StoreClock(
            now: { Date(timeIntervalSince1970: 1_728_032_400) },
            newId: { seq.next() },
            hlc: HLC(device: "testdevice1") { 1_728_032_400_000 }
        )
        return EntityStore(clock: clock)
    }

    private func sample(_ store: EntityStore) throws {
        try store.run("seed") { d, env in
            let area = try Commands.createArea(d, env, title: "Home")
            let tag = try Commands.createTag(d, env, title: "Errand")
            let p = try Commands.createProject(d, env, title: "Garden shed", areaId: area.id)
            let h = try Commands.createHeading(d, env, projectId: p.id, title: "Materials")
            let t = try Commands.createTodo(
                d, env,
                .init(
                    title: "Buy timber",
                    notes: "treated pine",
                    placement: .project(projectId: p.id, headingId: h.id)
                )
            )
            Commands.setTags(d, env, ids: [t.id], tagIds: [tag.id])
            _ = try Commands.addChecklistItem(d, env, todoId: t.id, title: "2x4s")
            _ = try Commands.createTodo(d, env, .init(title: "Call the plumber", placement: .inbox))
        }
    }

    @Test("round-trips an account with new ids")
    func roundTrip() throws {
        let source = store()
        try sample(source)
        let json = try Exchange.exportJson(source.entities, now: Date(timeIntervalSince1970: 1_728_032_400))
        #expect(!json.contains("\"clock\""))

        let target = store()
        let counts = try target.run("Import") { d, env in
            Commands.importData(d, env, try Exchange.parseImport(json))
        }
        #expect(counts.areas == 1)
        #expect(counts.projects == 1)
        #expect(counts.headings == 1)
        #expect(counts.todos == 2)
        #expect(counts.checklistItems == 1)
        #expect(counts.tags == 1)

        let e = target.entities
        let timber = e.todos.values.first { $0.title == "Buy timber" }!
        let project = e.projects[timber.projectId!]!
        #expect(project.title == "Garden shed")
        #expect(e.areas[project.areaId!]?.title == "Home")
        #expect(e.headings[timber.headingId!]?.projectId == project.id)
        #expect(timber.tagIds.compactMap { e.tags[$0]?.title } == ["Errand"])
        let checks = e.checklistItems.values.map { "\($0.title):\($0.todoId)" }
        #expect(checks == ["2x4s:\(timber.id)"])
        #expect(timber.notes == "treated pine")

        _ = target.undo()
        #expect(target.entities.todos.isEmpty)
    }

    @Test("import adds a copy rather than overwriting")
    func importCopies() throws {
        let s = store()
        try sample(s)
        let before = s.entities.todos.count
        let json = try Exchange.exportJson(s.entities, now: Date())
        try s.run("Import") { d, env in
            _ = Commands.importData(d, env, try Exchange.parseImport(json))
        }
        #expect(s.entities.todos.count == before * 2)
    }

    @Test("rejects non-export JSON")
    func rejectBad() {
        #expect(throws: Exchange.ImportError.self) {
            try Exchange.parseImport("{\"format\":\"nope\"}")
        }
        #expect(throws: Exchange.ImportError.self) {
            try Exchange.parseImport("not json")
        }
    }

    @Test("imports a Things intermediate export")
    func thingsImport() throws {
        let json = sampleThingsJSON()
        let data = try Exchange.parseImport(json)
        #expect(data.areas.count == 1)
        #expect(data.todos.count == 6)
        let daily = data.todos.first { $0.id == "todo-repeat" }?.repeat
        #expect(daily?.freq == .day)
        #expect(daily?.every == 1)
        #expect(daily?.mode == .fixed)
        #expect(daily?.anchor == "2026-11-08")
        let weekly = data.todos.first { $0.id == "todo-weekly" }?.repeat
        #expect(weekly?.freq == .week)
        #expect(weekly?.every == 2)
        #expect(weekly?.weekdays == [0, 2])
        #expect(weekly?.next == "2026-11-10")

        let target = store()
        let counts = try target.run("Import") { d, env in
            Commands.importData(d, env, try Exchange.parseImport(json))
        }
        #expect(counts.todos == 6)
        #expect(counts.checklistItems == 1)
        #expect(target.entities.todos.values.contains { $0.title == "Buy milk" && $0.start == .inbox })
    }

    private func sampleThingsJSON() -> String {
        """
        {
          "format": "dayrule-things-export",
          "version": 1,
          "thingsDatabaseVersion": 21,
          "exportedAt": "2026-11-07T12:00:00.000Z",
          "areas": [{ "id": "area-1", "title": "Personal", "order": 0 }],
          "tags": [{ "id": "tag-1", "title": "Errand", "order": 0 }],
          "projects": [{
            "id": "proj-1", "title": "Kitchen", "notes": "", "areaId": "area-1",
            "status": "open", "start": "ready", "order": 0, "tagIds": [],
            "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
          }],
          "headings": [{
            "id": "head-1", "projectId": "proj-1", "title": "Morning", "order": 0,
            "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
          }],
          "todos": [
            {
              "id": "todo-inbox", "title": "Buy milk", "notes": "", "status": "open",
              "start": "inbox", "order": 0, "tagIds": ["tag-1"],
              "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
            },
            {
              "id": "todo-sched", "title": "Scheduled chore", "notes": "",
              "projectId": "proj-1", "headingId": "head-1", "status": "open",
              "start": "ready", "startDate": "2020-01-01", "order": 1,
              "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
            },
            {
              "id": "todo-done", "title": "Old completed", "notes": "", "status": "completed",
              "start": "ready", "order": 2, "completedAt": "2026-10-01T00:00:00.000Z",
              "createdAt": "2026-09-01T00:00:00.000Z", "updatedAt": "2026-10-01T00:00:00.000Z"
            },
            {
              "id": "todo-later", "title": "Someday read", "notes": "", "areaId": "area-1",
              "status": "open", "start": "later", "order": 3,
              "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
            },
            {
              "id": "todo-repeat", "title": "Daily stretch", "notes": "", "status": "open",
              "start": "ready", "order": 4, "repeatTemplate": true, "repeatNext": "2026-11-08",
              "afterCompletion": false,
              "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
            },
            {
              "id": "todo-weekly", "title": "Gym", "notes": "", "status": "open",
              "start": "ready", "order": 5, "repeatTemplate": true, "repeatNext": "2026-11-10",
              "afterCompletion": false, "repeatFreq": "week", "repeatEvery": 2,
              "repeatWeekdays": [0, 2],
              "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
            }
          ],
          "checklistItems": [{
            "id": "check-1", "todoId": "todo-sched", "title": "Sub-step", "done": true, "order": 0,
            "createdAt": "2026-11-01T00:00:00.000Z", "updatedAt": "2026-11-01T00:00:00.000Z"
          }]
        }
        """
    }

    @Test("markdown export includes titles")
    func markdown() throws {
        let s = store()
        try sample(s)
        let md = Exchange.exportMarkdown(s.entities, now: Date())
        #expect(md.contains("Garden shed"))
        #expect(md.contains("Buy timber"))
        #expect(md.contains("Call the plumber"))
    }
}

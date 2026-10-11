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

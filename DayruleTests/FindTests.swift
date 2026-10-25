import Foundation
import Testing
@testable import Dayrule

@Suite("Quick Find")
struct FindTests {
    private let ctx = Lists.Context(today: "2026-10-04", keepVisible: nil)

    @Test func findsListsProjectsAndTodosByPrefixAndTypos() {
        let w = World()
        let p = w.project(title: "Garden shed")
        let t = w.todo(title: "Buy timber", notes: "treated pine", projectId: p.id, start: .ready)
        let f = Find.buildFinder(w.e, ctx)

        #expect(f.search("tod").first?.kind == .list)
        #expect(f.search("tod").first?.destination == .list(.today))
        #expect(f.search("gard").first?.kind == .project)
        #expect(f.search("gard").first?.destination == .project(p.id))
        let timber = f.search("timbr").first
        #expect(timber?.todoId == t.id)
        #expect(timber?.detail == "Garden shed")
        #expect(f.search("pine").first?.todoId == t.id)
        #expect(f.search("").isEmpty)
    }

    @Test func findsByTagAndRequiresEveryWord() {
        let w = World()
        let errand = w.tag(title: "Errand")
        let a = w.todo(title: "Post parcel", tagIds: [errand.id])
        _ = w.todo(title: "Post letter")
        let f = Find.buildFinder(w.e, ctx)
        #expect(f.search("errand").compactMap(\.todoId) == [a.id])
        #expect(f.search("post parcel").compactMap(\.todoId) == [a.id])
    }

    @Test func emptyContainerTitlesShowUntitledInDetail() {
        let w = World()
        let area = w.area(title: "")
        let project = w.project(title: "")
        let inArea = w.todo(title: "Wipe the tiles", areaId: area.id, start: .ready)
        let inProject = w.todo(title: "Buy brushes", projectId: project.id, start: .ready)
        let f = Find.buildFinder(w.e, ctx)
        #expect(f.search("tiles").first?.todoId == inArea.id)
        #expect(f.search("tiles").first?.detail == "Untitled area")
        #expect(f.search("brushes").first?.todoId == inProject.id)
        #expect(f.search("brushes").first?.detail == "Untitled project")
    }

    @Test func omitsTrashedProjectsAndAreas() {
        let w = World()
        _ = w.project(title: "Old plan", trashedAt: "2026-10-01T00:00:00Z")
        _ = w.area(title: "Old area", trashedAt: "2026-10-01T00:00:00Z")
        #expect(Find.buildFinder(w.e, ctx).search("old").isEmpty)
    }

    @Test func homeOfNamesTheList() {
        let w = World()
        func home(_ patch: (inout Todo) -> Void) -> ListName {
            var t = w.todo(start: .inbox)
            patch(&t)
            w.e.todos[t.id] = t
            return Find.homeOf(w.e, t, ctx).list
        }
        #expect(home { $0.start = .inbox } == .inbox)
        #expect(home { $0.start = .ready; $0.startDate = "2026-10-04" } == .today)
        #expect(home { $0.start = .ready; $0.deadline = "2026-10-03" } == .today)
        #expect(home { $0.start = .ready; $0.startDate = "2026-10-09" } == .scheduled)
        #expect(home { $0.start = .ready } == .backlog)
        #expect(home { $0.start = .later } == .notNow)
        #expect(home { $0.trashedAt = "2026-10-01T00:00:00Z" } == .trash)
        #expect(home {
            $0.status = .completed
            $0.completedAt = "2026-10-01T10:00:00Z"
        } == .done)
        let area = w.area()
        #expect(home { $0.areaId = area.id; $0.start = .ready } == .backlog)
    }
}

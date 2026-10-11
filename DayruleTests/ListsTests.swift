import Foundation
import Testing
@testable import Dayrule

@Suite("Lists")
struct ListsTests {
    private let ctx = Lists.Context(today: "2026-10-04", keepVisible: nil)

    private func ids(_ items: [ListItem]) -> [String] { items.map(\.id) }
    private func ids(_ todos: [Todo]) -> [String] { todos.map(\.id) }
    private func ids(_ projects: [Project]) -> [String] { projects.map(\.id) }
    private func ids(_ areas: [Area]) -> [String] { areas.map(\.id) }

    @Test("inbox holds unfiled open to-dos")
    func inboxBasic() throws {
        let w = World()
        let a = w.todo()
        let b = w.todo()
        w.todo(start: .ready)
        w.todo(start: .later)
        w.todo(trashedAt: "2026-10-02T00:00:00Z")
        #expect(ids(Lists.inbox(w.e, ctx)) == [a.id, b.id])
    }

    @Test("inbox never contains project or area to-dos")
    func inboxContainers() {
        let w = World()
        let p = w.project()
        let area = w.area()
        w.todo(projectId: p.id)
        w.todo(areaId: area.id)
        #expect(Lists.inbox(w.e, ctx).isEmpty)
    }

    @Test("today shows started or due items including projects")
    func todayBasic() {
        let w = World()
        let started = w.todo(start: .ready, startDate: "2026-10-04")
        let overdueStart = w.todo(start: .ready, startDate: "2026-09-30")
        let dueToday = w.todo(start: .ready, deadline: "2026-10-04")
        let tonight = w.todo(start: .ready, startDate: "2026-10-04", tonight: true)
        let project = w.project(startDate: "2026-10-04")
        w.todo(start: .ready, startDate: "2026-10-05")
        w.todo(start: .ready)
        let got = Set(ids(Lists.today(w.e, ctx)))
        #expect(got == Set([started.id, overdueStart.id, dueToday.id, project.id, tonight.id]))
    }

    @Test("today sorts by todayOrder")
    func todayOrder() {
        let w = World()
        let a = w.todo(start: .ready, startDate: "2026-10-04")
        let b = w.todo(start: .ready, startDate: "2026-10-04")
        w.setTodayOrder(b.id, "a0")
        w.setTodayOrder(a.id, "a1")
        #expect(ids(Lists.today(w.e, ctx)) == [b.id, a.id])
    }

    @Test("today excludes Later project children")
    func todayLaterProject() {
        let w = World()
        let p = w.project(start: .later)
        w.todo(projectId: p.id, start: .ready, startDate: "2026-10-04")
        #expect(Lists.today(w.e, ctx).isEmpty)
    }

    @Test("today keep-visible until logged")
    func todayLogging() {
        let w = World()
        let done = w.todo(
            status: .completed,
            start: .ready,
            startDate: "2026-10-04",
            completedAt: "2026-10-04T10:00:00Z"
        )
        w.e.settings.moveToDone = .immediately
        #expect(Lists.today(w.e, ctx).isEmpty)

        w.e.settings.moveToDone = .daily
        #expect(ids(Lists.today(w.e, ctx)) == [done.id])
        #expect(Lists.today(w.e, Lists.Context(today: "2026-10-05", keepVisible: nil)).isEmpty)

        w.e.settings.moveToDone = .manually
        #expect(ids(Lists.today(w.e, ctx)) == [done.id])
        w.e.settings.lastMovedToDoneAt = "2026-10-04T11:00:00Z"
        #expect(Lists.today(w.e, ctx).isEmpty)
    }

    @Test("scheduled next 7 days then months")
    func scheduledGroups() {
        let w = World()
        let tomorrow = w.todo(start: .ready, startDate: "2026-10-05")
        let day7 = w.todo(start: .ready, startDate: "2026-10-11")
        let day8 = w.todo(start: .ready, startDate: "2026-10-12")
        let nov = w.todo(start: .ready, startDate: "2026-11-20")
        w.todo(start: .ready, startDate: "2026-10-04")
        let u = Lists.scheduled(w.e, ctx)
        #expect(u.days.map(\.date) == [
            "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08",
            "2026-10-09", "2026-10-10", "2026-10-11",
        ])
        #expect(ids(u.days[0].items) == [tomorrow.id])
        #expect(ids(u.days[6].items) == [day7.id])
        #expect(u.months.map(\.month) == ["2026-10", "2026-11"])
        #expect(ids(u.months[0].items) == [day8.id])
        #expect(ids(u.months[1].items) == [nov.id])
    }

    @Test("backlog groups loose then area then projects")
    func backlogGroups() {
        let w = World()
        let area = w.area()
        let inArea = w.project(areaId: area.id)
        let loneProject = w.project()
        let loose = w.todo(start: .ready)
        let areaTodo = w.todo(areaId: area.id, start: .ready)
        let p1 = w.todo(projectId: inArea.id, start: .ready)
        let p2 = w.todo(projectId: loneProject.id, start: .ready)
        w.todo(start: .ready, startDate: "2026-10-05")
        w.todo()
        let groups = Lists.backlog(w.e, ctx)
        #expect(groups.map(\.container).map { c -> String in
            switch c {
            case .none: "none"
            case .area: "area"
            case .project: "project"
            }
        } == ["none", "area", "project", "project"])
        #expect(groups.map { ids($0.todos) } == [
            [loose.id], [areaTodo.id], [p1.id], [p2.id],
        ])
    }

    @Test("not now lists Later projects and loose Later to-dos")
    func notNowBasic() {
        let w = World()
        let p = w.project(start: .later)
        let t = w.todo(start: .later)
        w.todo(projectId: p.id, start: .later)
        let s = Lists.notNow(w.e, ctx)
        #expect(ids(s.projects) == [p.id])
        #expect(ids(s.todos) == [t.id])
    }

    @Test("trash lists directly trashed items")
    func trashBasic() {
        let w = World()
        let a = w.area(trashedAt: "2026-10-03T00:00:00Z")
        let t = w.todo(trashedAt: "2026-10-04T00:00:00Z")
        w.todo() // not trashed
        let tr = Lists.trash(w.e)
        #expect(ids(tr.areas) == [a.id])
        #expect(ids(tr.items) == [t.id])
    }

    @Test("sidebar counts open inbox/today/overdue")
    func counts() {
        let w = World()
        w.todo() // inbox
        w.todo(start: .ready, startDate: "2026-10-04")
        w.todo(start: .ready, deadline: "2026-10-01")
        let c = Lists.sidebarCounts(w.e, ctx)
        #expect(c.inbox == 1)
        #expect(c.today == 2)
        #expect(c.overdue == 1)
    }

    @Test("projectView groups to-dos under headings")
    func projectViewGroups() {
        let w = World()
        let p = w.project()
        let h = w.heading(projectId: p.id)
        let loose = w.todo(projectId: p.id, start: .ready)
        let under = w.todo(projectId: p.id, headingId: h.id, start: .ready)
        let archived = w.heading(projectId: p.id, title: "Archived", archived: true)
        let archivedUnder = w.todo(projectId: p.id, headingId: archived.id, start: .ready)
        let v = Lists.projectView(w.e, p.id, ctx)
        #expect(ids(v?.todos ?? []) == [loose.id, archivedUnder.id])
        #expect(v?.headings.map { ids($0.todos) } == [[under.id]])
        #expect(v?.headings.map(\.heading.id) == [h.id])
    }

    @Test("projectProgress counts non-canceled project to-dos")
    func projectProgressCounts() {
        let w = World()
        let p = w.project()
        w.todo(projectId: p.id, status: .completed)
        w.todo(projectId: p.id, status: .open)
        w.todo(projectId: p.id, status: .canceled)
        w.todo(projectId: p.id, trashedAt: "2026-10-02T00:00:00Z")
        let prog = Lists.projectProgress(w.e, p.id)
        #expect(prog.done == 1)
        #expect(prog.total == 2)
    }
}

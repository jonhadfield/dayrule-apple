import Foundation
@testable import Dayrule

/// Test fixture builder (web `domain/fixtures.ts`).
final class World {
    var e = Entities.empty()
    private var n = 0
    private let ts = "2026-10-01T09:00:00.000Z"

    private func nextId(_ prefix: String) -> ID {
        n += 1
        return "\(prefix)-\(String(format: "%04d", n))"
    }

    private func orderIn(_ keys: [OrderKey]) -> OrderKey {
        (try? Order.keyAfterLast(keys)) ?? (try! Order.keyBetween(nil, nil))
    }

    @discardableResult
    func area(
        title: String = "Area",
        tagIds: [ID] = [],
        trashedAt: Timestamp? = nil
    ) -> Area {
        let a = Area(
            id: nextId("area"),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: title,
            order: orderIn(e.areas.values.map(\.order)),
            tagIds: tagIds,
            trashedAt: trashedAt
        )
        e.areas[a.id] = a
        return a
    }

    @discardableResult
    func project(
        title: String = "Project",
        areaId: ID? = nil,
        status: Status = .open,
        start: StartBucket = .ready,
        startDate: LocalDate? = nil,
        tonight: Bool = false,
        deadline: LocalDate? = nil,
        tagIds: [ID] = [],
        completedAt: Timestamp? = nil,
        trashedAt: Timestamp? = nil
    ) -> Project {
        let p = Project(
            id: nextId("proj"),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: title,
            notes: "",
            areaId: areaId,
            status: status,
            start: start,
            startDate: startDate,
            tonight: tonight,
            deadline: deadline,
            tagIds: tagIds,
            order: orderIn(e.projects.values.map(\.order)),
            todayOrder: nil,
            completedAt: completedAt,
            trashedAt: trashedAt
        )
        e.projects[p.id] = p
        return p
    }

    @discardableResult
    func tag(title: String = "Tag", parentId: ID? = nil) -> Tag {
        let t = Tag(
            id: nextId("tag"),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: title,
            parentId: parentId,
            order: orderIn(e.tags.values.map(\.order))
        )
        e.tags[t.id] = t
        return t
    }

    @discardableResult
    func heading(projectId: ID, title: String = "Heading", archived: Bool = false) -> Heading {
        let h = Heading(
            id: nextId("head"),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            projectId: projectId,
            title: title,
            order: orderIn(e.headings.values.filter { $0.projectId == projectId }.map(\.order)),
            archived: archived
        )
        e.headings[h.id] = h
        return h
    }

    @discardableResult
    func todo(
        title: String = "To-do",
        notes: String = "",
        projectId: ID? = nil,
        headingId: ID? = nil,
        areaId: ID? = nil,
        status: Status = .open,
        start: StartBucket = .inbox,
        startDate: LocalDate? = nil,
        tonight: Bool = false,
        deadline: LocalDate? = nil,
        tagIds: [ID] = [],
        todayOrder: OrderKey? = nil,
        completedAt: Timestamp? = nil,
        trashedAt: Timestamp? = nil
    ) -> Todo {
        var t = Todo(
            id: nextId("todo"),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: title,
            notes: notes,
            projectId: projectId,
            headingId: headingId,
            areaId: areaId,
            status: status,
            start: start,
            startDate: startDate,
            tonight: tonight,
            deadline: deadline,
            tagIds: tagIds,
            order: orderIn(e.todos.values.map(\.order)),
            todayOrder: todayOrder,
            completedAt: completedAt,
            trashedAt: trashedAt,
            reminderAt: nil,
            repeat: nil,
            repeatTemplateId: nil
        )
        e.todos[t.id] = t
        return t
    }

    func setTodayOrder(_ id: ID, _ key: OrderKey) {
        e.todos[id]?.todayOrder = key
    }
}

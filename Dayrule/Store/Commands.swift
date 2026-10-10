import Foundation

enum Commands {
    enum Placement: Sendable, Equatable {
        case inbox, today, ready, later
        case project(projectId: ID, headingId: ID?)
        case area(areaId: ID)
    }

    struct NewTodo: Sendable {
        var title: String = ""
        var notes: String = ""
        var placement: Placement
    }

    enum When: Sendable, Equatable {
        case today
        case date(LocalDate)
        case later
        case ready
        case clear

        init(_ result: WhenResult) {
            switch result {
            case .today: self = .today
            case .later: self = .later
            case .date(let d): self = .date(d)
            }
        }
    }

    @discardableResult
    static func createTodo(_ d: Draft, _ env: EntityStore.Env, _ input: NewTodo) throws -> Todo {
        let p = input.placement
        let siblings = d.allTodos().filter { t in
            switch p {
            case let .project(projectId, headingId):
                return t.projectId == projectId && t.headingId == headingId
            case let .area(areaId):
                return t.areaId == areaId && t.projectId == nil
            default:
                return t.projectId == nil && t.areaId == nil
            }
        }
        let order = try Order.keyAfterLast(siblings.map(\.order))
        let ts = ISOStamp.format(env.now)
        var todo = Todo(
            id: env.newId(),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: input.title,
            notes: input.notes,
            projectId: nil,
            headingId: nil,
            areaId: nil,
            status: .open,
            start: .ready,
            startDate: nil,
            tonight: false,
            deadline: nil,
            tagIds: [],
            order: order,
            todayOrder: nil,
            completedAt: nil,
            trashedAt: nil,
            reminderAt: nil,
            repeat: nil,
            repeatTemplateId: nil
        )
        switch p {
        case .inbox:
            todo.start = .inbox
        case .today:
            todo.startDate = env.today
            todo.todayOrder = try Order.keyAfterLast(todayKeys(d, env))
        case .later:
            todo.start = .later
        case .ready:
            break
        case let .project(projectId, headingId):
            todo.projectId = projectId
            todo.headingId = headingId
        case let .area(areaId):
            todo.areaId = areaId
        }
        d.putTodo(todo)
        return todo
    }

    static func updateTodo(_ d: Draft, _ env: EntityStore.Env, id: ID, title: String?, notes: String?) {
        guard var t = d.getTodo(id) else { return }
        if let title { t.title = title }
        if let notes { t.notes = notes }
        t.updatedAt = ISOStamp.format(env.now)
        d.putTodo(t)
    }

    static func updateProject(_ d: Draft, _ env: EntityStore.Env, id: ID, title: String?, notes: String?) {
        guard var p = d.getProject(id) else { return }
        if let title { p.title = title }
        if let notes { p.notes = notes }
        p.updatedAt = ISOStamp.format(env.now)
        d.putProject(p)
    }

    @discardableResult
    static func createProject(_ d: Draft, _ env: EntityStore.Env, title: String, areaId: ID? = nil) throws -> Project {
        let siblings = d.allProjects().filter { $0.areaId == areaId }
        let ts = ISOStamp.format(env.now)
        let project = Project(
            id: env.newId(),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: title,
            notes: "",
            areaId: areaId,
            status: .open,
            start: .ready,
            startDate: nil,
            tonight: false,
            deadline: nil,
            tagIds: [],
            order: try Order.keyAfterLast(siblings.map(\.order)),
            todayOrder: nil,
            completedAt: nil,
            trashedAt: nil
        )
        d.putProject(project)
        return project
    }

    @discardableResult
    static func createArea(_ d: Draft, _ env: EntityStore.Env, title: String) throws -> Area {
        let ts = ISOStamp.format(env.now)
        let area = Area(
            id: env.newId(),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: title,
            order: try Order.keyAfterLast(d.allAreas().map(\.order)),
            tagIds: [],
            trashedAt: nil
        )
        d.putArea(area)
        return area
    }

    static func renameArea(_ d: Draft, _ env: EntityStore.Env, id: ID, title: String) {
        guard var a = d.getArea(id) else { return }
        a.title = title
        a.updatedAt = ISOStamp.format(env.now)
        d.putArea(a)
    }

    static func setDeadline(_ d: Draft, _ env: EntityStore.Env, ids: [ID], deadline: LocalDate?) {
        let ts = ISOStamp.format(env.now)
        for id in ids {
            if var t = d.getTodo(id) {
                t.deadline = deadline
                t.updatedAt = ts
                d.putTodo(t)
            } else if var p = d.getProject(id) {
                p.deadline = deadline
                p.updatedAt = ts
                d.putProject(p)
            }
        }
    }

    static func setStatus(_ d: Draft, _ env: EntityStore.Env, ids: [ID], status: Status) {
        let completedAt: Timestamp? = status == .open ? nil : ISOStamp.format(env.now)
        for id in ids {
            if var item = d.getTodo(id), item.status != status {
                item.status = status
                item.completedAt = completedAt
                item.updatedAt = ISOStamp.format(env.now)
                d.putTodo(item)
                if status != .open {
                    Repeats.onInstanceDone(d, env, instance: item)
                }
            } else if var item = d.getProject(id), item.status != status {
                item.status = status
                item.completedAt = completedAt
                item.updatedAt = ISOStamp.format(env.now)
                d.putProject(item)
                if status != .open {
                    for var t in d.allTodos() where t.projectId == id && t.status == .open {
                        t.status = status
                        t.completedAt = completedAt
                        t.updatedAt = ISOStamp.format(env.now)
                        d.putTodo(t)
                    }
                }
            }
        }
    }

    static func setWhen(_ d: Draft, _ env: EntityStore.Env, ids: [ID], when: When) throws {
        for id in ids {
            if var t = d.getTodo(id) {
                try applyWhen(&t.start, startDate: &t.startDate, tonight: &t.tonight, todayOrder: &t.todayOrder, itemStartDate: t.startDate, d: d, env: env, when: when)
                t.updatedAt = ISOStamp.format(env.now)
                d.putTodo(t)
            } else if var p = d.getProject(id) {
                var start = p.start
                try applyWhen(&start, startDate: &p.startDate, tonight: &p.tonight, todayOrder: &p.todayOrder, itemStartDate: p.startDate, d: d, env: env, when: when)
                if start != .inbox { p.start = start }
                p.updatedAt = ISOStamp.format(env.now)
                d.putProject(p)
            }
        }
    }

    static func trashItems(_ d: Draft, _ env: EntityStore.Env, ids: [ID]) {
        let ts = ISOStamp.format(env.now)
        for id in ids {
            if var item = d.getTodo(id), item.trashedAt == nil {
                item.trashedAt = ts
                item.updatedAt = ts
                d.putTodo(item)
            } else if var item = d.getProject(id), item.trashedAt == nil {
                item.trashedAt = ts
                item.updatedAt = ts
                d.putProject(item)
            } else if var area = d.getArea(id), area.trashedAt == nil {
                area.trashedAt = ts
                area.updatedAt = ts
                d.putArea(area)
            }
        }
    }

    static func restoreItems(_ d: Draft, _ env: EntityStore.Env, ids: [ID]) {
        let ts = ISOStamp.format(env.now)
        for id in ids {
            if var item = d.getTodo(id), item.trashedAt != nil {
                item.trashedAt = nil
                item.updatedAt = ts
                d.putTodo(item)
            } else if var item = d.getProject(id), item.trashedAt != nil {
                item.trashedAt = nil
                item.updatedAt = ts
                d.putProject(item)
            } else if var area = d.getArea(id), area.trashedAt != nil {
                area.trashedAt = nil
                area.updatedAt = ts
                d.putArea(area)
            }
        }
    }

    static func setDoneMode(_ d: Draft, mode: DoneMode) {
        var s = d.settings
        s.moveToDone = mode
        d.setSettings(s)
    }

    /// "Log Completed" for manual logging mode (web `moveToDoneNow`).
    static func moveToDoneNow(_ d: Draft, _ env: EntityStore.Env) {
        var s = d.settings
        s.lastMovedToDoneAt = ISOStamp.format(env.now)
        d.setSettings(s)
    }

    @discardableResult
    static func createHeading(_ d: Draft, _ env: EntityStore.Env, projectId: ID, title: String) throws -> Heading {
        let siblings = d.allHeadings().filter { $0.projectId == projectId }
        let ts = ISOStamp.format(env.now)
        let heading = Heading(
            id: env.newId(),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            projectId: projectId,
            title: title,
            order: try Order.keyAfterLast(siblings.map(\.order)),
            archived: false
        )
        d.putHeading(heading)
        return heading
    }

    static func updateHeading(_ d: Draft, _ env: EntityStore.Env, id: ID, title: String?, archived: Bool?) {
        guard var h = d.getHeading(id) else { return }
        if let title { h.title = title }
        if let archived { h.archived = archived }
        h.updatedAt = ISOStamp.format(env.now)
        d.putHeading(h)
    }

    static func deleteHeading(_ d: Draft, _ env: EntityStore.Env, id: ID) {
        let ts = ISOStamp.format(env.now)
        for var t in d.allTodos() where t.headingId == id {
            t.headingId = nil
            t.updatedAt = ts
            d.putTodo(t)
        }
        d.remove(.headings, id: id)
    }

    @discardableResult
    static func createTag(_ d: Draft, _ env: EntityStore.Env, title: String, parentId: ID? = nil) throws -> Tag {
        let ts = ISOStamp.format(env.now)
        let tag = Tag(
            id: env.newId(),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            title: title,
            parentId: parentId,
            order: try Order.keyAfterLast(d.allTags().map(\.order))
        )
        d.putTag(tag)
        return tag
    }

    static func setTags(_ d: Draft, _ env: EntityStore.Env, ids: [ID], tagIds: [ID]) {
        let ts = ISOStamp.format(env.now)
        for id in ids {
            if var t = d.getTodo(id) {
                t.tagIds = tagIds
                t.updatedAt = ts
                d.putTodo(t)
            } else if var p = d.getProject(id) {
                p.tagIds = tagIds
                p.updatedAt = ts
                d.putProject(p)
            }
        }
    }

    /// Permanently delete trashed items and everything inside them (web `emptyTrash`).
    static func emptyTrash(_ d: Draft) {
        let areaIds = Set(d.allAreas().filter { $0.trashedAt != nil }.map(\.id))
        let projectIds = Set(
            d.allProjects()
                .filter { $0.trashedAt != nil || ($0.areaId.map { areaIds.contains($0) } ?? false) }
                .map(\.id)
        )
        let todoIds = Set(
            d.allTodos()
                .filter {
                    $0.trashedAt != nil
                        || ($0.projectId.map { projectIds.contains($0) } ?? false)
                        || ($0.areaId.map { areaIds.contains($0) } ?? false)
                }
                .map(\.id)
        )
        for id in areaIds { d.remove(.areas, id: id) }
        for id in projectIds { d.remove(.projects, id: id) }
        for id in todoIds { d.remove(.todos, id: id) }
        for h in d.allHeadings() where projectIds.contains(h.projectId) {
            d.remove(.headings, id: h.id)
        }
        for c in d.allChecklistItems() where todoIds.contains(c.todoId) {
            d.remove(.checklistItems, id: c.id)
        }
    }

    // MARK: - Helpers

    private static func todayKeys(_ d: Draft, _ env: EntityStore.Env) -> [OrderKey] {
        let todos = d.allTodos().filter { t in
            guard let sd = t.startDate else { return false }
            return sd <= env.today
        }.map { $0.todayOrder ?? $0.order }
        let projects = d.allProjects().filter { p in
            guard let sd = p.startDate else { return false }
            return sd <= env.today
        }.map { $0.todayOrder ?? $0.order }
        return todos + projects
    }

    private static func applyWhen(
        _ start: inout StartBucket,
        startDate: inout LocalDate?,
        tonight: inout Bool,
        todayOrder: inout OrderKey?,
        itemStartDate: LocalDate?,
        d: Draft,
        env: EntityStore.Env,
        when: When
    ) throws {
        switch when {
        case .today:
            start = .ready
            startDate = env.today
            tonight = false
        case .date(let date):
            start = .ready
            startDate = date
            tonight = false
        case .later:
            start = .later
            startDate = nil
            tonight = false
        case .ready:
            start = .ready
            startDate = nil
            tonight = false
        case .clear:
            startDate = nil
            tonight = false
        }
        let entersToday =
            startDate != nil
            && startDate! <= env.today
            && !(itemStartDate != nil && itemStartDate! <= env.today)
        if entersToday {
            todayOrder = try Order.keyAfterLast(todayKeys(d, env))
        }
    }
}

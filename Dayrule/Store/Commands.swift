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

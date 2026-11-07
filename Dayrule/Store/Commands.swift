import Foundation

enum Commands {
    struct CommandError: Error, LocalizedError, Sendable {
        var message: String
        var errorDescription: String? { message }
    }

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
        case inbox
        case clear

        init(_ result: WhenResult) {
            switch result {
            case .today: self = .today
            case .later: self = .later
            case .date(let d): self = .date(d)
            }
        }
    }

    /// Destination for `moveTodos` (web `MoveTarget`).
    enum MoveTarget: Sendable, Equatable {
        case inbox
        case none
        case area(areaId: ID)
        case project(projectId: ID, headingId: ID? = nil)
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

    /// Move to-dos into Inbox, out of any project/area, into an area, or into a project
    /// (web `moveTodos`). Reorders into the destination sibling list.
    static func moveTodos(_ d: Draft, _ env: EntityStore.Env, ids: [ID], target: MoveTarget) throws {
        let ts = ISOStamp.format(env.now)
        for id in ids {
            guard var t = d.getTodo(id) else { continue }
            let siblings = d.allTodos().filter { s in
                if s.id == id { return false }
                switch target {
                case let .project(projectId, headingId):
                    return s.projectId == projectId && s.headingId == headingId
                case let .area(areaId):
                    return s.areaId == areaId && s.projectId == nil
                case .inbox, .none:
                    return s.projectId == nil && s.areaId == nil
                }
            }
            switch target {
            case let .project(projectId, headingId):
                t.projectId = projectId
                t.headingId = headingId
                t.areaId = nil
            case let .area(areaId):
                t.projectId = nil
                t.headingId = nil
                t.areaId = areaId
            case .inbox, .none:
                t.projectId = nil
                t.headingId = nil
                t.areaId = nil
            }
            t.order = try Order.keyAfterLast(siblings.map(\.order))
            if case .inbox = target {
                t.start = .inbox
                t.startDate = nil
                t.tonight = false
            } else if t.start == .inbox {
                t.start = .ready
            }
            t.updatedAt = ts
            d.putTodo(t)
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

    /// Set or clear a reminder (`YYYY-MM-DDTHH:mm`, or nil). On a repeat
    /// template, stores `HH:mm` in `repeat.reminderTime` (web `setReminder`).
    static func setReminder(_ d: Draft, _ env: EntityStore.Env, ids: [ID], at: String?) {
        let ts = ISOStamp.format(env.now)
        for id in ids {
            guard var t = d.getTodo(id) else { continue }
            if var rule = t.repeat {
                if let at, at.count >= 16 {
                    rule.reminderTime = String(at.dropFirst(11).prefix(5))
                } else {
                    rule.reminderTime = nil
                }
                t.repeat = rule
            } else {
                t.reminderAt = at
            }
            t.updatedAt = ts
            d.putTodo(t)
        }
    }

    @discardableResult
    static func addChecklistItem(
        _ d: Draft,
        _ env: EntityStore.Env,
        todoId: ID,
        title: String
    ) throws -> ChecklistItem {
        let ts = ISOStamp.format(env.now)
        let siblings = d.allChecklistItems().filter { $0.todoId == todoId }
        let item = ChecklistItem(
            id: env.newId(),
            createdAt: ts,
            updatedAt: ts,
            clock: nil,
            todoId: todoId,
            title: title,
            done: false,
            order: try Order.keyAfterLast(siblings.map(\.order))
        )
        d.putChecklistItem(item)
        return item
    }

    static func updateChecklistItem(
        _ d: Draft,
        _ env: EntityStore.Env,
        id: ID,
        title: String? = nil,
        done: Bool? = nil
    ) {
        guard var c = d.getChecklistItem(id) else { return }
        if let title { c.title = title }
        if let done { c.done = done }
        c.updatedAt = ISOStamp.format(env.now)
        d.putChecklistItem(c)
    }

    static func removeChecklistItem(_ d: Draft, id: ID) {
        d.remove(.checklistItems, id: id)
    }

    /// Turn a project into a to-do. Child to-dos become checklist items; headings
    /// are dropped. The project and its children are removed (web `convertProjectToTodo`).
    @discardableResult
    static func convertProjectToTodo(_ d: Draft, _ env: EntityStore.Env, projectId: ID) throws -> Todo {
        guard let p = d.getProject(projectId) else {
            throw CommandError(message: "project not found")
        }
        let children = d.allTodos()
            .filter { $0.projectId == projectId && $0.trashedAt == nil }
            .sorted { Order.compareKeys($0.order, $1.order) < 0 }

        let placement: Placement = p.areaId.map { .area(areaId: $0) } ?? .ready
        var todo = try createTodo(d, env, .init(title: p.title, notes: p.notes, placement: placement))

        let status: Status = p.status == .canceled ? .open : p.status
        if p.startDate != nil {
            todo.start = .ready
        } else if p.start == .later {
            todo.start = .later
        }
        todo.status = status
        todo.tagIds = p.tagIds
        if let startDate = p.startDate { todo.startDate = startDate }
        if let deadline = p.deadline { todo.deadline = deadline }
        if status != .open {
            todo.completedAt = p.completedAt ?? ISOStamp.format(env.now)
        }
        if let startDate = p.startDate, startDate <= env.today {
            todo.todayOrder = try Order.keyAfterLast(todayKeys(d, env))
        }
        todo.updatedAt = ISOStamp.format(env.now)
        d.putTodo(todo)

        for c in children {
            let item = try addChecklistItem(d, env, todoId: todo.id, title: c.title)
            if c.status == .completed {
                updateChecklistItem(d, env, id: item.id, done: true)
            }
            for ch in d.allChecklistItems() where ch.todoId == c.id {
                d.remove(.checklistItems, id: ch.id)
            }
            d.remove(.todos, id: c.id)
        }
        for h in d.allHeadings() where h.projectId == projectId {
            d.remove(.headings, id: h.id)
        }
        d.remove(.projects, id: projectId)
        guard let result = d.getTodo(todo.id) else {
            throw CommandError(message: "project not found")
        }
        return result
    }

    struct ImportCounts: Equatable, Sendable {
        var areas: Int
        var projects: Int
        var headings: Int
        var todos: Int
        var checklistItems: Int
        var tags: Int
    }

    /// Copy an export's records in with new ids, remapping references
    /// (web `importData`). Never overwrites existing data.
    @discardableResult
    static func importData(
        _ d: Draft,
        _ env: EntityStore.Env,
        _ data: Exchange.ExportData
    ) -> ImportCounts {
        let now = ISOStamp.format(env.now)
        var map: [ID: ID] = [:]
        func fresh(_ old: ID) -> ID {
            let id = env.newId()
            map[old] = id
            return id
        }
        for x in data.areas { _ = fresh(x.id) }
        for x in data.projects { _ = fresh(x.id) }
        for x in data.headings { _ = fresh(x.id) }
        for x in data.todos { _ = fresh(x.id) }
        for x in data.checklistItems { _ = fresh(x.id) }
        for x in data.tags { _ = fresh(x.id) }

        func ref(_ old: ID?) -> ID? {
            guard let old else { return nil }
            return map[old]
        }
        func refs(_ olds: [ID]) -> [ID] {
            olds.compactMap { map[$0] }
        }

        for t in data.tags {
            var copy = t
            copy.id = map[t.id]!
            copy.parentId = ref(t.parentId)
            copy.updatedAt = now
            copy.clock = nil
            d.putTag(copy)
        }
        for a in data.areas {
            var copy = a
            copy.id = map[a.id]!
            copy.tagIds = refs(a.tagIds)
            copy.updatedAt = now
            copy.clock = nil
            d.putArea(copy)
        }
        for p in data.projects {
            var copy = p
            copy.id = map[p.id]!
            copy.areaId = ref(p.areaId)
            copy.tagIds = refs(p.tagIds)
            copy.updatedAt = now
            copy.clock = nil
            d.putProject(copy)
        }
        var headingProjects: [ID: ID] = [:]
        var headingCount = 0
        for h in data.headings {
            guard let projectId = ref(h.projectId) else { continue }
            let newId = map[h.id]!
            headingProjects[newId] = projectId
            headingCount += 1
            var copy = h
            copy.id = newId
            copy.projectId = projectId
            copy.updatedAt = now
            copy.clock = nil
            d.putHeading(copy)
        }
        for t in data.todos {
            let projectId = ref(t.projectId)
            let headingId = ref(t.headingId)
            var copy = t
            copy.id = map[t.id]!
            copy.projectId = projectId
            if let headingId, let projectId, headingProjects[headingId] == projectId {
                copy.headingId = headingId
            } else {
                copy.headingId = nil
            }
            copy.areaId = projectId != nil ? nil : ref(t.areaId)
            copy.tagIds = refs(t.tagIds)
            copy.repeatTemplateId = ref(t.repeatTemplateId)
            copy.updatedAt = now
            copy.clock = nil
            d.putTodo(copy)
        }
        var checklist = 0
        for c in data.checklistItems {
            guard let todoId = ref(c.todoId) else { continue }
            checklist += 1
            var copy = c
            copy.id = map[c.id]!
            copy.todoId = todoId
            copy.updatedAt = now
            copy.clock = nil
            d.putChecklistItem(copy)
        }
        return ImportCounts(
            areas: data.areas.count,
            projects: data.projects.count,
            headings: headingCount,
            todos: data.todos.count,
            checklistItems: checklist,
            tags: data.tags.count
        )
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

    enum OrderField: Sendable {
        case order
        case todayOrder
    }

    enum ReorderCollection: Sendable {
        case todos
        case projects
        case areas
        case headings
        case tags
    }

    /// Place an item between two neighbours; only the moved item's key changes
    /// (web `commands.reorder`).
    static func reorder(
        _ d: Draft,
        _ env: EntityStore.Env,
        collection: ReorderCollection,
        id: ID,
        field: OrderField,
        before: ID?,
        after: ID?
    ) throws {
        func keyOf(_ nid: ID?) -> OrderKey? {
            guard let nid else { return nil }
            switch collection {
            case .todos:
                guard let n = d.getTodo(nid) else { return nil }
                return field == .todayOrder ? (n.todayOrder ?? n.order) : n.order
            case .projects:
                guard let n = d.getProject(nid) else { return nil }
                return field == .todayOrder ? (n.todayOrder ?? n.order) : n.order
            case .areas:
                return d.getArea(nid)?.order
            case .headings:
                return d.getHeading(nid)?.order
            case .tags:
                return d.getTag(nid)?.order
            }
        }
        let key = try Order.keyBetween(keyOf(before), keyOf(after))
        let ts = ISOStamp.format(env.now)
        switch collection {
        case .todos:
            guard var t = d.getTodo(id) else { return }
            if field == .todayOrder { t.todayOrder = key } else { t.order = key }
            t.updatedAt = ts
            d.putTodo(t)
        case .projects:
            guard var p = d.getProject(id) else { return }
            if field == .todayOrder { p.todayOrder = key } else { p.order = key }
            p.updatedAt = ts
            d.putProject(p)
        case .areas:
            guard var a = d.getArea(id) else { return }
            a.order = key
            a.updatedAt = ts
            d.putArea(a)
        case .headings:
            guard var h = d.getHeading(id) else { return }
            h.order = key
            h.updatedAt = ts
            d.putHeading(h)
        case .tags:
            guard var t = d.getTag(id) else { return }
            t.order = key
            t.updatedAt = ts
            d.putTag(t)
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
        case .inbox:
            start = .inbox
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

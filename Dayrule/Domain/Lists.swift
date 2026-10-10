import Foundation

/// List selectors (web `domain/lists.ts`, PLAN §5.2).
enum Lists {
    struct Context: Equatable, Sendable {
        var today: LocalDate
        var keepVisible: Set<ID>?
    }

    // MARK: - Effective state

    static func projectOf(_ e: Entities, _ t: Todo) -> Project? {
        guard let id = t.projectId else { return nil }
        return e.projects[id]
    }

    private static func areaTrashed(_ e: Entities, _ areaId: ID?) -> Bool {
        guard let areaId, let a = e.areas[areaId] else { return false }
        return a.trashedAt != nil
    }

    static func isTrashed(_ e: Entities, _ item: ListItem) -> Bool {
        if item.trashedAt != nil { return true }
        if let p = item.asProject {
            return areaTrashed(e, p.areaId)
        }
        if let t = item.asTodo {
            if let project = projectOf(e, t) {
                return isTrashed(e, .project(project))
            }
            return areaTrashed(e, t.areaId)
        }
        return false
    }

    private static func localDateOf(_ ts: String) -> LocalDate {
        // ISO timestamps → local calendar day (web uses `new Date(ts)`).
        let plain = ISO8601DateFormatter()
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: ts) ?? plain.date(from: ts) {
            return When.toLocalDate(d)
        }
        // Already a date or truncated "YYYY-MM-DD…"
        return String(ts.prefix(10))
    }

    static func isInDone(_ e: Entities, _ item: ListItem, _ ctx: Context) -> Bool {
        if item.status == .open || item.completedAt == nil { return false }
        if ctx.keepVisible?.contains(item.id) == true { return false }
        switch e.settings.moveToDone {
        case .immediately:
            return true
        case .daily:
            return localDateOf(item.completedAt!) < ctx.today
        case .manually:
            guard let at = e.settings.lastMovedToDoneAt else { return false }
            return item.completedAt! <= at
        }
    }

    static func isTemplate(_ item: ListItem) -> Bool {
        item.asTodo?.repeat != nil
    }

    static func isVisible(_ e: Entities, _ item: ListItem, _ ctx: Context) -> Bool {
        if isTemplate(item) || isTrashed(e, item) || isInDone(e, item, ctx) { return false }
        if let t = item.asTodo, let project = projectOf(e, t) {
            if project.status != .open, isInDone(e, .project(project), ctx) {
                return false
            }
        }
        return true
    }

    static func effectiveStart(_ e: Entities, _ item: ListItem) -> StartBucket {
        if let t = item.asTodo {
            if projectOf(e, t)?.start == .later { return .later }
            if t.start == .inbox, t.projectId != nil || t.areaId != nil {
                return .ready
            }
            return t.start
        }
        return item.start
    }

    private static func byOrder(_ a: ListItem, _ b: ListItem) -> Bool {
        let c = Order.compareKeys(a.order, b.order)
        if c != 0 { return c < 0 }
        return Order.compareKeys(a.id, b.id) < 0
    }

    private static func byTodayOrder(_ a: ListItem, _ b: ListItem) -> Bool {
        let c = Order.compareKeys(a.todayOrder ?? a.order, b.todayOrder ?? b.order)
        if c != 0 { return c < 0 }
        return Order.compareKeys(a.id, b.id) < 0
    }

    private static func items(_ e: Entities) -> [ListItem] {
        e.todos.values.map(ListItem.todo) + e.projects.values.map(ListItem.project)
    }

    // MARK: - Lists

    static func inbox(_ e: Entities, _ ctx: Context) -> [Todo] {
        e.todos.values
            .filter { isVisible(e, .todo($0), ctx) && effectiveStart(e, .todo($0)) == .inbox }
            .sorted { byOrder(.todo($0), .todo($1)) }
    }

    private static func isDueToday(_ item: ListItem, _ ctx: Context) -> Bool {
        (item.startDate.map { $0 <= ctx.today } ?? false)
            || (item.deadline.map { $0 <= ctx.today } ?? false)
    }

    static func today(_ e: Entities, _ ctx: Context) -> [ListItem] {
        items(e)
            .filter {
                isVisible(e, $0, ctx)
                    && effectiveStart(e, $0) != .later
                    && isDueToday($0, ctx)
            }
            .sorted(by: byTodayOrder)
    }

    static func isOverdue(_ item: ListItem, _ ctx: Context) -> Bool {
        item.status == .open
            && item.deadline.map { $0 < ctx.today } == true
    }

    struct DayGroup: Equatable, Sendable {
        var date: LocalDate
        var items: [ListItem]
    }

    struct MonthGroup: Equatable, Sendable {
        var month: String
        var items: [ListItem]
    }

    struct ScheduledList: Equatable, Sendable {
        var days: [DayGroup]
        var months: [MonthGroup]
        var waiting: [ListItem]
    }

    static func scheduledDate(_ i: ListItem) -> LocalDate? {
        if let t = i.asTodo, let r = t.repeat { return r.next }
        return i.startDate
    }

    static func scheduled(_ e: Entities, _ ctx: Context) -> ScheduledList {
        func dated(_ i: ListItem) -> Bool {
            guard let date = scheduledDate(i) else { return false }
            return date > ctx.today
        }
        let scheduled = items(e)
            .filter { i in
                i.status == .open
                    && effectiveStart(e, i) != .later
                    && dated(i)
                    && (isTemplate(i) ? !isTrashed(e, i) : isVisible(e, i, ctx))
            }
            .sorted {
                let c = Order.compareKeys(scheduledDate($0) ?? "", scheduledDate($1) ?? "")
                if c != 0 { return c < 0 }
                return byOrder($0, $1)
            }

        let days: [DayGroup] = (1...7).map { n in
            let date = When.addLocalDays(ctx.today, n)
            return DayGroup(date: date, items: scheduled.filter { scheduledDate($0) == date })
        }
        let lastDay = days.last?.date ?? ctx.today

        var months: [MonthGroup] = []
        for i in scheduled {
            guard let d = scheduledDate(i), d > lastDay else { continue }
            let month = String(d.prefix(7))
            if let last = months.indices.last, months[last].month == month {
                months[last].items.append(i)
            } else {
                months.append(MonthGroup(month: month, items: [i]))
            }
        }

        let waiting = e.todos.values
            .filter { t in
                guard let r = t.repeat else { return false }
                return r.next == nil && !isTrashed(e, .todo(t))
            }
            .map(ListItem.todo)
            .sorted(by: byOrder)

        return ScheduledList(days: days, months: months, waiting: waiting)
    }

    enum Container: Equatable, Sendable {
        case none
        case area(Area)
        case project(Project)
    }

    struct Group: Equatable, Sendable {
        var container: Container
        var todos: [Todo]
    }

    private static func isAvailable(_ e: Entities, _ t: Todo, _ ctx: Context) -> Bool {
        isVisible(e, .todo(t), ctx)
            && effectiveStart(e, .todo(t)) == .ready
            && (t.startDate == nil || t.startDate! <= ctx.today)
    }

    static func backlog(_ e: Entities, _ ctx: Context) -> [Group] {
        var groups: [String: Group] = [:]
        func groupFor(_ t: Todo) -> Group {
            let project = projectOf(e, t)
            let area = t.areaId.flatMap { e.areas[$0] }
            let key = project.map { "p:\($0.id)" } ?? area.map { "a:\($0.id)" } ?? "none"
            if let g = groups[key] { return g }
            let container: Container = {
                if let project { return .project(project) }
                if let area { return .area(area) }
                return .none
            }()
            let g = Group(container: container, todos: [])
            groups[key] = g
            return g
        }

        for t in e.todos.values {
            guard isAvailable(e, t, ctx) else { continue }
            if let project = projectOf(e, t), project.status != .open { continue }
            let key = projectOf(e, t).map { "p:\($0.id)" }
                ?? t.areaId.flatMap { e.areas[$0] }.map { "a:\($0.id)" }
                ?? "none"
            var g = groupFor(t)
            g.todos.append(t)
            groups[key] = g
        }

        func rank(_ g: Group) -> (Int, String, String) {
            switch g.container {
            case .none: return (0, "", "")
            case .area(let a): return (1, a.order, "")
            case .project(let p):
                let area = p.areaId.flatMap { e.areas[$0] }
                return (area != nil ? 1 : 2, area?.order ?? "", p.order)
            }
        }

        return groups.values
            .map { Group(container: $0.container, todos: $0.todos.sorted { byOrder(.todo($0), .todo($1)) }) }
            .sorted {
                let ra = rank($0), rb = rank($1)
                if ra.0 != rb.0 { return ra.0 < rb.0 }
                let c1 = Order.compareKeys(ra.1, rb.1)
                if c1 != 0 { return c1 < 0 }
                return Order.compareKeys(ra.2, rb.2) < 0
            }
    }

    struct NotNowList: Equatable, Sendable {
        var projects: [Project]
        var todos: [Todo]
    }

    static func notNow(_ e: Entities, _ ctx: Context) -> NotNowList {
        NotNowList(
            projects: e.projects.values
                .filter { isVisible(e, .project($0), ctx) && $0.start == .later }
                .sorted { byOrder(.project($0), .project($1)) },
            todos: e.todos.values
                .filter {
                    isVisible(e, .todo($0), ctx)
                        && $0.start == .later
                        && projectOf(e, $0)?.start != .later
                }
                .sorted { byOrder(.todo($0), .todo($1)) }
        )
    }

    struct DoneDay: Equatable, Sendable {
        var date: LocalDate
        var items: [ListItem]
    }

    static func doneList(_ e: Entities, _ ctx: Context) -> [DoneDay] {
        let logged = items(e)
            .filter { !isTrashed(e, $0) && isInDone(e, $0, ctx) }
            .sorted { Order.compareKeys($1.completedAt ?? "", $0.completedAt ?? "") < 0 }

        var days: [DoneDay] = []
        for i in logged {
            let date = localDateOf(i.completedAt ?? "")
            if let last = days.indices.last, days[last].date == date {
                days[last].items.append(i)
            } else {
                days.append(DoneDay(date: date, items: [i]))
            }
        }
        return days
    }

    struct TrashList: Equatable, Sendable {
        var areas: [Area]
        var items: [ListItem]
    }

    static func trash(_ e: Entities) -> TrashList {
        TrashList(
            areas: e.areas.values.filter { $0.trashedAt != nil }
                .sorted { Order.compareKeys($1.trashedAt ?? "", $0.trashedAt ?? "") < 0 },
            items: items(e).filter { $0.trashedAt != nil }
                .sorted { Order.compareKeys($1.trashedAt ?? "", $0.trashedAt ?? "") < 0 }
        )
    }

    struct SidebarCounts: Equatable, Sendable {
        var inbox: Int
        var today: Int
        var overdue: Int
    }

    static func sidebarCounts(_ e: Entities, _ ctx: Context) -> SidebarCounts {
        let t = today(e, ctx)
        let open = t.filter { $0.status == .open }
        return SidebarCounts(
            inbox: inbox(e, ctx).filter { $0.status == .open }.count,
            today: open.count,
            overdue: open.filter { isOverdue($0, ctx) }.count
        )
    }
}

import Foundation

/// Repeating to-dos (web `store/repeats.ts`, PLAN §4.2).
enum Repeats {
    static func instanceId(templateId: ID, date: LocalDate) -> ID {
        UuidV5.generate(name: "\(templateId)/\(date)")
    }

    /// Make a to-do repeat, change the rule, or stop (nil removes the template).
    static func setRepeat(
        _ d: Draft,
        _ env: EntityStore.Env,
        id: ID,
        rule: RepeatRule?
    ) {
        guard var t = d.getTodo(id) else { return }
        let now = ISOStamp.format(env.now)
        guard let rule else {
            for c in d.allChecklistItems() where c.todoId == id {
                d.remove(.checklistItems, id: c.id)
            }
            d.remove(.todos, id: id)
            return
        }
        let from = t.repeat != nil ? When.addLocalDays(env.today, 1) : env.today
        let next: LocalDate? = {
            if t.repeat != nil, rule.mode == .afterCompletion, t.repeat?.next == nil {
                return nil
            }
            return firstDue(rule, from: from)
        }()
        t.status = .open
        if t.start == .inbox { t.start = .ready }
        t.startDate = nil
        t.tonight = false
        t.completedAt = nil
        t.repeatTemplateId = nil
        var stamped = rule
        stamped.next = next
        t.repeat = stamped
        t.updatedAt = now
        d.putTodo(t)
    }

    /// Create due instances; returns `collection/id` keys of created records.
    @discardableResult
    static func generateRepeats(_ d: Draft, _ env: EntityStore.Env) -> Set<String> {
        var created = Set<String>()
        for template in d.allTodos() {
            guard var r = template.repeat, let nextDue = r.next else { continue }
            guard nextDue <= env.today, template.trashedAt == nil else { continue }
            var date: LocalDate
            var next: LocalDate?
            if r.mode == .fixed {
                date = nextDue
                var candidate = RepeatMath.occurrenceAfter(r, date)
                while candidate <= env.today {
                    date = candidate
                    candidate = RepeatMath.occurrenceAfter(r, date)
                }
                next = candidate
            } else {
                date = nextDue
                next = nil
            }
            makeInstance(d, template: template, date: date, created: &created)
            r.next = next
            var updated = template
            updated.repeat = r
            updated.updatedAt = ISOStamp.format(env.now)
            d.putTodo(updated)
        }
        return created
    }

    /// An after-completion instance was done: schedule the template's next.
    static func onInstanceDone(_ d: Draft, _ env: EntityStore.Env, instance: Todo) {
        guard let templateId = instance.repeatTemplateId else { return }
        guard var template = d.getTodo(templateId), var r = template.repeat else { return }
        guard r.mode == .afterCompletion, r.next == nil else { return }
        r.next = RepeatMath.dueAfterCompletion(r, env.today)
        template.repeat = r
        template.updatedAt = ISOStamp.format(env.now)
        d.putTodo(template)
    }

    private static func firstDue(_ r: RepeatRule, from: LocalDate) -> LocalDate {
        let start = r.anchor > from ? r.anchor : from
        return r.mode == .fixed ? RepeatMath.occurrenceOnOrAfter(r, start) : start
    }

    private static func makeInstance(
        _ d: Draft,
        template: Todo,
        date: LocalDate,
        created: inout Set<String>
    ) {
        let id = instanceId(templateId: template.id, date: date)
        if d.getTodo(id) != nil { return }
        let at = "\(date)T00:00:00.000Z"
        let instance = Todo(
            id: id,
            createdAt: at,
            updatedAt: at,
            clock: nil,
            title: template.title,
            notes: template.notes,
            projectId: template.projectId,
            headingId: template.headingId,
            areaId: template.areaId,
            status: .open,
            start: .ready,
            startDate: date,
            tonight: false,
            deadline: nil,
            tagIds: template.tagIds,
            order: template.order,
            todayOrder: nil,
            completedAt: nil,
            trashedAt: nil,
            reminderAt: template.repeat?.reminderTime.map { "\(date)T\($0)" },
            repeat: nil,
            repeatTemplateId: template.id
        )
        d.putTodo(instance)
        created.insert("todos/\(id)")
        for c in d.allChecklistItems() where c.todoId == template.id {
            let cid = UuidV5.generate(name: "\(id)/\(c.id)")
            let copy = ChecklistItem(
                id: cid,
                createdAt: at,
                updatedAt: at,
                clock: nil,
                todoId: id,
                title: c.title,
                done: false,
                order: c.order
            )
            d.putChecklistItem(copy)
            created.insert("checklistItems/\(cid)")
        }
    }
}

import Foundation

/// Dictionary ↔ typed entity with unknown-field side bag (PLAN §5.3).
enum EntityJSON {
    private static let epoch = "1970-01-01T00:00:00.000Z"
    private static let defaultOrder: OrderKey = "a0"

    private static let areaKeys: Set<String> = [
        "type", "id", "createdAt", "updatedAt", "clock", "title", "order", "tagIds", "trashedAt",
    ]
    private static let projectKeys: Set<String> = [
        "type", "id", "createdAt", "updatedAt", "clock", "title", "notes", "areaId", "status",
        "start", "startDate", "tonight", "deadline", "tagIds", "order", "todayOrder",
        "completedAt", "trashedAt",
    ]
    private static let headingKeys: Set<String> = [
        "type", "id", "createdAt", "updatedAt", "clock", "projectId", "title", "order", "archived",
    ]
    private static let todoKeys: Set<String> = [
        "type", "id", "createdAt", "updatedAt", "clock", "title", "notes", "projectId", "headingId",
        "areaId", "status", "start", "startDate", "tonight", "deadline", "tagIds", "order",
        "todayOrder", "completedAt", "trashedAt", "reminderAt", "repeat", "repeatTemplateId",
    ]
    private static let checklistKeys: Set<String> = [
        "type", "id", "createdAt", "updatedAt", "clock", "todoId", "title", "done", "order",
    ]
    private static let tagKeys: Set<String> = [
        "type", "id", "createdAt", "updatedAt", "clock", "title", "parentId", "order",
    ]
    private static let settingsKeys: Set<String> = [
        "type", "clock", "moveToDone", "lastMovedToDoneAt",
    ]

    /// Insert a decrypted sync `v` object into `entities` by collection prefix of `key`.
    @discardableResult
    static func insert(key: String, value: [String: Any], into entities: inout Entities) -> Bool {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let collection = parts[0]
        let id = (value["id"] as? String) ?? parts[1]
        switch collection {
        case "todos":
            entities.todos[id] = decodeTodo(value, id: id)
            return true
        case "projects":
            entities.projects[id] = decodeProject(value, id: id)
            return true
        case "areas":
            entities.areas[id] = decodeArea(value, id: id)
            return true
        case "headings":
            entities.headings[id] = decodeHeading(value, id: id)
            return true
        case "checklistItems":
            entities.checklistItems[id] = decodeChecklist(value, id: id)
            return true
        case "tags":
            entities.tags[id] = decodeTag(value, id: id)
            return true
        case "settings":
            entities.settings = decodeSettings(value)
            return true
        default:
            return false
        }
    }

    static func encode(_ t: Todo) -> [String: Any] {
        var d: [String: Any] = [
            "type": "todo",
            "id": t.id,
            "createdAt": t.createdAt,
            "updatedAt": t.updatedAt,
            "title": t.title,
            "notes": t.notes,
            "status": t.status.rawValue,
            "start": t.start.rawValue,
            "tonight": t.tonight,
            "tagIds": t.tagIds,
            "order": t.order,
        ]
        putOptional(&d, "clock", t.clock)
        putOptional(&d, "projectId", t.projectId)
        putOptional(&d, "headingId", t.headingId)
        putOptional(&d, "areaId", t.areaId)
        putOptional(&d, "startDate", t.startDate)
        putOptional(&d, "deadline", t.deadline)
        putOptional(&d, "todayOrder", t.todayOrder)
        putOptional(&d, "completedAt", t.completedAt)
        putOptional(&d, "trashedAt", t.trashedAt)
        putOptional(&d, "reminderAt", t.reminderAt)
        putOptional(&d, "repeatTemplateId", t.repeatTemplateId)
        if let r = t.repeat { d["repeat"] = encodeRepeat(r) }
        for (k, v) in t.unknown { d[k] = v.toAny() }
        return d
    }

    static func encode(_ p: Project) -> [String: Any] {
        var d: [String: Any] = [
            "type": "project",
            "id": p.id,
            "createdAt": p.createdAt,
            "updatedAt": p.updatedAt,
            "title": p.title,
            "notes": p.notes,
            "status": p.status.rawValue,
            "start": p.start.rawValue,
            "tonight": p.tonight,
            "tagIds": p.tagIds,
            "order": p.order,
        ]
        putOptional(&d, "clock", p.clock)
        putOptional(&d, "areaId", p.areaId)
        putOptional(&d, "startDate", p.startDate)
        putOptional(&d, "deadline", p.deadline)
        putOptional(&d, "todayOrder", p.todayOrder)
        putOptional(&d, "completedAt", p.completedAt)
        putOptional(&d, "trashedAt", p.trashedAt)
        for (k, v) in p.unknown { d[k] = v.toAny() }
        return d
    }

    static func encode(_ a: Area) -> [String: Any] {
        var d: [String: Any] = [
            "type": "area",
            "id": a.id,
            "createdAt": a.createdAt,
            "updatedAt": a.updatedAt,
            "title": a.title,
            "order": a.order,
            "tagIds": a.tagIds,
        ]
        putOptional(&d, "clock", a.clock)
        putOptional(&d, "trashedAt", a.trashedAt)
        for (k, v) in a.unknown { d[k] = v.toAny() }
        return d
    }

    static func encode(_ c: ChecklistItem) -> [String: Any] {
        var d: [String: Any] = [
            "type": "checklistItem",
            "id": c.id,
            "createdAt": c.createdAt,
            "updatedAt": c.updatedAt,
            "todoId": c.todoId,
            "title": c.title,
            "done": c.done,
            "order": c.order,
        ]
        putOptional(&d, "clock", c.clock)
        for (k, v) in c.unknown { d[k] = v.toAny() }
        return d
    }

    // MARK: - Decode

    static func decodeTodo(_ v: [String: Any], id: ID) -> Todo {
        Todo(
            id: id,
            createdAt: string(v, "createdAt") ?? epoch,
            updatedAt: string(v, "updatedAt") ?? epoch,
            clock: clock(v),
            title: string(v, "title") ?? "",
            notes: string(v, "notes") ?? "",
            projectId: string(v, "projectId"),
            headingId: string(v, "headingId"),
            areaId: string(v, "areaId"),
            status: Status(rawValue: string(v, "status") ?? "") ?? .open,
            start: StartBucket(rawValue: string(v, "start") ?? "") ?? .inbox,
            startDate: string(v, "startDate"),
            tonight: bool(v, "tonight"),
            deadline: string(v, "deadline"),
            tagIds: stringArray(v, "tagIds"),
            order: string(v, "order") ?? defaultOrder,
            todayOrder: string(v, "todayOrder"),
            completedAt: string(v, "completedAt"),
            trashedAt: string(v, "trashedAt"),
            reminderAt: string(v, "reminderAt"),
            repeat: decodeRepeat(v["repeat"]),
            repeatTemplateId: string(v, "repeatTemplateId"),
            unknown: unknown(v, known: todoKeys)
        )
    }

    static func decodeProject(_ v: [String: Any], id: ID) -> Project {
        let start = StartBucket(rawValue: string(v, "start") ?? "") ?? .ready
        return Project(
            id: id,
            createdAt: string(v, "createdAt") ?? epoch,
            updatedAt: string(v, "updatedAt") ?? epoch,
            clock: clock(v),
            title: string(v, "title") ?? "",
            notes: string(v, "notes") ?? "",
            areaId: string(v, "areaId"),
            status: Status(rawValue: string(v, "status") ?? "") ?? .open,
            start: start == .inbox ? .ready : start,
            startDate: string(v, "startDate"),
            tonight: bool(v, "tonight"),
            deadline: string(v, "deadline"),
            tagIds: stringArray(v, "tagIds"),
            order: string(v, "order") ?? defaultOrder,
            todayOrder: string(v, "todayOrder"),
            completedAt: string(v, "completedAt"),
            trashedAt: string(v, "trashedAt"),
            unknown: unknown(v, known: projectKeys)
        )
    }

    static func decodeArea(_ v: [String: Any], id: ID) -> Area {
        Area(
            id: id,
            createdAt: string(v, "createdAt") ?? epoch,
            updatedAt: string(v, "updatedAt") ?? epoch,
            clock: clock(v),
            title: string(v, "title") ?? "",
            order: string(v, "order") ?? defaultOrder,
            tagIds: stringArray(v, "tagIds"),
            trashedAt: string(v, "trashedAt"),
            unknown: unknown(v, known: areaKeys)
        )
    }

    static func decodeHeading(_ v: [String: Any], id: ID) -> Heading {
        Heading(
            id: id,
            createdAt: string(v, "createdAt") ?? epoch,
            updatedAt: string(v, "updatedAt") ?? epoch,
            clock: clock(v),
            projectId: string(v, "projectId") ?? "",
            title: string(v, "title") ?? "",
            order: string(v, "order") ?? defaultOrder,
            archived: bool(v, "archived"),
            unknown: unknown(v, known: headingKeys)
        )
    }

    static func decodeChecklist(_ v: [String: Any], id: ID) -> ChecklistItem {
        ChecklistItem(
            id: id,
            createdAt: string(v, "createdAt") ?? epoch,
            updatedAt: string(v, "updatedAt") ?? epoch,
            clock: clock(v),
            todoId: string(v, "todoId") ?? "",
            title: string(v, "title") ?? "",
            done: bool(v, "done"),
            order: string(v, "order") ?? defaultOrder,
            unknown: unknown(v, known: checklistKeys)
        )
    }

    static func decodeTag(_ v: [String: Any], id: ID) -> Tag {
        Tag(
            id: id,
            createdAt: string(v, "createdAt") ?? epoch,
            updatedAt: string(v, "updatedAt") ?? epoch,
            clock: clock(v),
            title: string(v, "title") ?? "",
            parentId: string(v, "parentId"),
            order: string(v, "order") ?? defaultOrder,
            unknown: unknown(v, known: tagKeys)
        )
    }

    static func decodeSettings(_ v: [String: Any]) -> Settings {
        Settings(
            clock: clock(v),
            moveToDone: DoneMode(rawValue: string(v, "moveToDone") ?? "") ?? .immediately,
            lastMovedToDoneAt: string(v, "lastMovedToDoneAt"),
            unknown: unknown(v, known: settingsKeys)
        )
    }

    // MARK: - Helpers

    private static func unknown(_ v: [String: Any], known: Set<String>) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (k, val) in v where !known.contains(k) {
            out[k] = JSONValue.fromAny(val)
        }
        return out
    }

    private static func clock(_ v: [String: Any]) -> FieldClock? {
        guard let raw = v["clock"] as? [String: Any] else {
            return v["clock"] as? FieldClock
        }
        var out: FieldClock = [:]
        for (k, val) in raw {
            if let s = val as? String { out[k] = s }
        }
        return out.isEmpty ? nil : out
    }

    private static func string(_ v: [String: Any], _ key: String) -> String? {
        v[key] as? String
    }

    private static func stringArray(_ v: [String: Any], _ key: String) -> [String] {
        (v[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func bool(_ v: [String: Any], _ key: String) -> Bool {
        if let b = v[key] as? Bool { return b }
        if let n = v[key] as? NSNumber { return n.boolValue }
        return false
    }

    private static func decodeRepeat(_ any: Any?) -> RepeatRule? {
        guard let d = any as? [String: Any] else { return nil }
        guard
            let freq = RepeatRule.Freq(rawValue: d["freq"] as? String ?? ""),
            let mode = RepeatRule.Mode(rawValue: d["mode"] as? String ?? ""),
            let anchor = d["anchor"] as? String
        else { return nil }
        let every: Int = {
            if let i = d["every"] as? Int { return i }
            if let n = d["every"] as? NSNumber { return n.intValue }
            return 1
        }()
        let weekdays = (d["weekdays"] as? [Any])?.compactMap { v -> Int? in
            if let i = v as? Int { return i }
            if let n = v as? NSNumber { return n.intValue }
            return nil
        }
        return RepeatRule(
            freq: freq,
            every: every,
            weekdays: weekdays,
            mode: mode,
            anchor: anchor,
            next: d["next"] as? String,
            reminderTime: d["reminderTime"] as? String
        )
    }

    private static func encodeRepeat(_ r: RepeatRule) -> [String: Any] {
        var d: [String: Any] = [
            "freq": r.freq.rawValue,
            "every": r.every,
            "mode": r.mode.rawValue,
            "anchor": r.anchor,
        ]
        if let w = r.weekdays { d["weekdays"] = w }
        putOptional(&d, "next", r.next)
        putOptional(&d, "reminderTime", r.reminderTime)
        return d
    }

    private static func putOptional(_ d: inout [String: Any], _ key: String, _ value: Any?) {
        if let value { d[key] = value }
    }
}

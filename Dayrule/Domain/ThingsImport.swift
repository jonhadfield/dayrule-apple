import Foundation

/// Things 3 intermediate JSON → Dayrule export records (web `domain/things.ts`, PLAN §8.3).
enum ThingsImport {
    static let format = "dayrule-things-export"
    static let version = 1

    static func looksLike(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return raw["format"] as? String == format
    }

    static func parseAndMap(_ text: String) throws -> Exchange.ExportData {
        do {
            return try map(parse(text))
        } catch let err as Exchange.ImportError {
            throw err
        } catch {
            throw Exchange.ImportError(message: error.localizedDescription)
        }
    }

    // MARK: - Parse

    private struct Document {
        var exportedAt: String
        var areas: [[String: Any]]
        var tags: [[String: Any]]
        var projects: [[String: Any]]
        var headings: [[String: Any]]
        var todos: [[String: Any]]
        var checklistItems: [[String: Any]]
    }

    private static func parse(_ text: String) throws -> Document {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw Exchange.ImportError(message: "This file isn’t valid JSON.")
        }
        guard raw["format"] as? String == format else {
            throw Exchange.ImportError(message: "This isn’t a Things export from things-export.")
        }
        let versionNum = (raw["version"] as? Int) ?? (raw["version"] as? NSNumber)?.intValue
        guard versionNum == version else {
            let v = raw["version"].map { String(describing: $0) } ?? "?"
            throw Exchange.ImportError(
                message: "This Things export is format version \(v); this app reads version \(version)."
            )
        }
        return Document(
            exportedAt: raw["exportedAt"] as? String ?? "",
            areas: try list(raw, "areas"),
            tags: try list(raw, "tags"),
            projects: try list(raw, "projects"),
            headings: try list(raw, "headings"),
            todos: try list(raw, "todos"),
            checklistItems: try list(raw, "checklistItems")
        )
    }

    private static func list(_ raw: [String: Any], _ key: String) throws -> [[String: Any]] {
        let v = raw[key] ?? []
        guard let arr = v as? [Any], arr.allSatisfy({ $0 is [String: Any] }) else {
            throw Exchange.ImportError(message: "\"\(key)\" must be a list.")
        }
        if arr.count > 100_000 {
            throw Exchange.ImportError(message: "Too many \(key).")
        }
        return arr.compactMap { $0 as? [String: Any] }
    }

    // MARK: - Map

    private static func map(_ src: Document) throws -> Exchange.ExportData {
        let stamp = src.exportedAt.isEmpty ? "1970-01-01T00:00:00.000Z" : src.exportedAt
        let tagOrder = try orderKeys(src.tags)
        let areaOrder = try orderKeys(src.areas)
        let projectOrder = try orderKeys(src.projects)
        let headingOrder = try orderKeys(src.headings)
        let todoOrder = try orderKeys(src.todos)
        let checkOrder = try orderKeys(src.checklistItems)
        let projectToday = try todayOrders(src.projects)
        let todoToday = try todayOrders(src.todos)

        let tagIds = Set(src.tags.compactMap { $0["id"] as? String })
        let areaIds = Set(src.areas.compactMap { $0["id"] as? String })
        let projectIds = Set(src.projects.compactMap { $0["id"] as? String })
        let headingIds = Set(src.headings.compactMap { $0["id"] as? String })
        let todoIds = Set(src.todos.compactMap { $0["id"] as? String })

        let tags: [Tag] = src.tags.compactMap { t in
            guard let id = t["id"] as? String else { return nil }
            let parent = t["parentId"] as? String
            return Tag(
                id: id,
                createdAt: stamp,
                updatedAt: stamp,
                clock: nil,
                title: string(t["title"]).isEmpty ? "Untitled" : string(t["title"]),
                parentId: parent.flatMap { tagIds.contains($0) ? $0 : nil },
                order: tagOrder[id]!,
                unknown: [:]
            )
        }

        let areas: [Area] = src.areas.compactMap { a in
            guard let id = a["id"] as? String else { return nil }
            return Area(
                id: id,
                createdAt: stamp,
                updatedAt: stamp,
                clock: nil,
                title: string(a["title"]).isEmpty ? "Untitled" : string(a["title"]),
                order: areaOrder[id]!,
                tagIds: filterIds(a["tagIds"], keep: tagIds),
                trashedAt: bool(a["trashed"]) ? stamp : nil,
                unknown: [:]
            )
        }

        let projects: [Project] = src.projects.compactMap { p in
            guard let id = p["id"] as? String else { return nil }
            let areaId = p["areaId"] as? String
            return Project(
                id: id,
                createdAt: string(p["createdAt"], fallback: stamp),
                updatedAt: string(p["updatedAt"], fallback: stamp),
                clock: nil,
                title: string(p["title"]).isEmpty ? "Untitled" : string(p["title"]),
                notes: string(p["notes"]),
                areaId: areaId.flatMap { areaIds.contains($0) ? $0 : nil },
                status: status(p["status"]),
                start: projectStart(p["start"]),
                startDate: localDate(p["startDate"]),
                tonight: false,
                deadline: localDate(p["deadline"]),
                tagIds: filterIds(p["tagIds"], keep: tagIds),
                order: projectOrder[id]!,
                todayOrder: projectToday[id],
                completedAt: p["completedAt"] as? String,
                trashedAt: p["trashedAt"] as? String,
                unknown: [:]
            )
        }

        let headings: [Heading] = src.headings.compactMap { h in
            guard let id = h["id"] as? String,
                  let projectId = h["projectId"] as? String,
                  projectIds.contains(projectId)
            else { return nil }
            return Heading(
                id: id,
                createdAt: string(h["createdAt"], fallback: stamp),
                updatedAt: string(h["updatedAt"], fallback: stamp),
                clock: nil,
                projectId: projectId,
                title: string(h["title"]).isEmpty ? "Untitled" : string(h["title"]),
                order: headingOrder[id]!,
                archived: bool(h["archived"]),
                unknown: [:]
            )
        }

        let todos: [Todo] = src.todos.compactMap { t in
            guard let id = t["id"] as? String else { return nil }
            let projectId = (t["projectId"] as? String).flatMap { projectIds.contains($0) ? $0 : nil }
            let headingId = (t["headingId"] as? String).flatMap {
                headingIds.contains($0) && projectId != nil ? $0 : nil
            }
            let areaId = projectId == nil
                ? (t["areaId"] as? String).flatMap { areaIds.contains($0) ? $0 : nil }
                : nil
            let rule = asRepeat(t)
            return Todo(
                id: id,
                createdAt: string(t["createdAt"], fallback: stamp),
                updatedAt: string(t["updatedAt"], fallback: stamp),
                clock: nil,
                title: string(t["title"]).isEmpty ? "Untitled" : string(t["title"]),
                notes: string(t["notes"]),
                projectId: projectId,
                headingId: headingId,
                areaId: areaId,
                status: status(t["status"]),
                start: todoStart(t["start"]),
                startDate: rule == nil ? localDate(t["startDate"]) : nil,
                tonight: false,
                deadline: localDate(t["deadline"]),
                tagIds: filterIds(t["tagIds"], keep: tagIds),
                order: todoOrder[id]!,
                todayOrder: todoToday[id],
                completedAt: t["completedAt"] as? String,
                trashedAt: t["trashedAt"] as? String,
                reminderAt: t["reminderAt"] as? String,
                repeat: rule,
                repeatTemplateId: nil,
                unknown: [:]
            )
        }

        let checklistItems: [ChecklistItem] = src.checklistItems.compactMap { c in
            guard let id = c["id"] as? String,
                  let todoId = c["todoId"] as? String,
                  todoIds.contains(todoId)
            else { return nil }
            return ChecklistItem(
                id: id,
                createdAt: string(c["createdAt"], fallback: stamp),
                updatedAt: string(c["updatedAt"], fallback: stamp),
                clock: nil,
                todoId: todoId,
                title: string(c["title"]).isEmpty ? "Untitled" : string(c["title"]),
                done: bool(c["done"]),
                order: checkOrder[id]!,
                unknown: [:]
            )
        }

        return Exchange.ExportData(
            areas: areas,
            projects: projects,
            headings: headings,
            todos: todos,
            checklistItems: checklistItems,
            tags: tags
        )
    }

    private static func asRepeat(_ t: [String: Any]) -> RepeatRule? {
        guard bool(t["repeatTemplate"]) else { return nil }
        let created = string(t["createdAt"])
        let anchor =
            localDate(t["repeatNext"])
            ?? localDate(t["startDate"])
            ?? (created.count >= 10 ? String(created.prefix(10)) : nil)
        guard let anchor, dateOK(anchor) else { return nil }

        let freqRaw = t["repeatFreq"] as? String ?? "day"
        let freq = RepeatRule.Freq(rawValue: freqRaw) ?? .day
        let everyNum = (t["repeatEvery"] as? Int) ?? (t["repeatEvery"] as? NSNumber)?.intValue
        let every = (everyNum != nil && everyNum! >= 1) ? everyNum! : 1

        var weekdays: [Int]?
        if freq == .week, let arr = t["repeatWeekdays"] as? [Any] {
            let days = arr.compactMap { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue }
                .filter { (0...6).contains($0) }
            let unique = Array(Set(days)).sorted()
            if !unique.isEmpty { weekdays = unique }
        }

        let after = bool(t["afterCompletion"])
        return RepeatRule(
            freq: freq,
            every: every,
            weekdays: weekdays,
            mode: after ? .afterCompletion : .fixed,
            anchor: anchor,
            next: after ? nil : (localDate(t["repeatNext"]) ?? anchor),
            reminderTime: nil
        )
    }

    // MARK: - Helpers

    private static func orderKeys(_ items: [[String: Any]]) throws -> [String: OrderKey] {
        let parsed: [(id: String, order: Int)] = items.compactMap { r in
            guard let id = r["id"] as? String else { return nil }
            let order = (r["order"] as? Int) ?? (r["order"] as? NSNumber)?.intValue ?? 0
            return (id, order)
        }
        let sorted = parsed.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
        let keys = try Order.keysBetween(nil, nil, max(sorted.count, 1))
        var map: [String: OrderKey] = [:]
        for (i, item) in sorted.enumerated() {
            map[item.id] = keys[i]
        }
        return map
    }

    private static func todayOrders(_ items: [[String: Any]]) throws -> [String: OrderKey] {
        let withToday: [(id: String, todayOrder: Int)] = items.compactMap { r in
            guard let id = r["id"] as? String else { return nil }
            let t = (r["todayOrder"] as? Int) ?? (r["todayOrder"] as? NSNumber)?.intValue
            guard let t else { return nil }
            return (id, t)
        }
        guard !withToday.isEmpty else { return [:] }
        let sorted = withToday.sorted {
            if $0.todayOrder != $1.todayOrder { return $0.todayOrder < $1.todayOrder }
            return $0.id < $1.id
        }
        let keys = try Order.keysBetween(nil, nil, sorted.count)
        var map: [String: OrderKey] = [:]
        for (i, item) in sorted.enumerated() {
            map[item.id] = keys[i]
        }
        return map
    }

    private static func string(_ v: Any?, fallback: String = "") -> String {
        if let s = v as? String { return s }
        return fallback
    }

    private static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return false
    }

    private static func localDate(_ v: Any?) -> LocalDate? {
        guard let s = v as? String, dateOK(s) else { return nil }
        return s
    }

    private static func dateOK(_ s: String) -> Bool {
        s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func filterIds(_ v: Any?, keep: Set<String>) -> [ID] {
        guard let arr = v as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }.filter { keep.contains($0) }
    }

    private static func status(_ v: Any?) -> Status {
        Status(rawValue: string(v, fallback: "open")) ?? .open
    }

    private static func todoStart(_ v: Any?) -> StartBucket {
        StartBucket(rawValue: string(v, fallback: "ready")) ?? .ready
    }

    private static func projectStart(_ v: Any?) -> StartBucket {
        let s = StartBucket(rawValue: string(v, fallback: "ready")) ?? .ready
        return s == .inbox ? .ready : s
    }
}

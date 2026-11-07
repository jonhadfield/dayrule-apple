import Foundation

/// Export / import (`dayrule-export` v1 + Things intermediate, web `domain/exchange.ts`, PLAN §12).
enum Exchange {
    static let format = "dayrule-export"
    static let version = 1

    struct ExportData: Equatable, Sendable {
        var areas: [Area]
        var projects: [Project]
        var headings: [Heading]
        var todos: [Todo]
        var checklistItems: [ChecklistItem]
        var tags: [Tag]
    }

    struct ImportError: Error, LocalizedError, Equatable {
        var message: String
        var errorDescription: String? { message }
    }

    // MARK: - Export

    static func exportJson(_ e: Entities, now: Date) throws -> String {
        let payload: [String: Any] = [
            "format": format,
            "version": version,
            "exportedAt": ISOStamp.format(now),
            "areas": e.areas.values.map { stripClock(EntityJSON.encode($0)) },
            "projects": e.projects.values.map { stripClock(EntityJSON.encode($0)) },
            "headings": e.headings.values.map { stripClock(EntityJSON.encode($0)) },
            "todos": e.todos.values.map { stripClock(EntityJSON.encode($0)) },
            "checklistItems": e.checklistItems.values.map { stripClock(EntityJSON.encode($0)) },
            "tags": e.tags.values.map { stripClock(EntityJSON.encode($0)) },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportError(message: "Couldn’t encode export.")
        }
        return text
    }

    static func exportMarkdown(_ e: Entities, now: Date) -> String {
        func live<T>(_ xs: [T], trashed: (T) -> Timestamp?) -> [T] {
            xs.filter { trashed($0) == nil }
        }
        func ordered<T>(_ xs: [T], order: (T) -> OrderKey, id: (T) -> ID) -> [T] {
            xs.sorted {
                let c = Order.compareKeys(order($0), order($1))
                if c != 0 { return c < 0 }
                return Order.compareKeys(id($0), id($1)) < 0
            }
        }
        func tagNames(_ ids: [ID]) -> [String] {
            ids.compactMap { e.tags[$0]?.title }.map { "#\($0)" }
        }
        func line(_ t: Todo) -> String {
            let box: String
            switch t.status {
            case .completed: box = "[x]"
            case .canceled: box = "[-]"
            case .open: box = "[ ]"
            }
            var bits = [t.title.isEmpty ? "Untitled" : t.title]
            if let d = t.startDate { bits.append("(when: \(d))") }
            if let d = t.deadline { bits.append("(deadline: \(d))") }
            bits.append(contentsOf: tagNames(t.tagIds))
            var out = ["- \(box) \(bits.joined(separator: " "))"]
            for n in t.notes.split(separator: "\n").map(String.init) where !n.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append("  > \(n)")
            }
            let checks = ordered(
                e.checklistItems.values.filter { $0.todoId == t.id }.map { $0 },
                order: \.order, id: \.id
            )
            for c in checks {
                out.append("  - \(c.done ? "[x]" : "[ ]") \(c.title)")
            }
            return out.joined(separator: "\n")
        }

        let todos = live(Array(e.todos.values), trashed: \.trashedAt)
        var parts: [String] = [
            "# Dayrule export",
            "",
            "Exported \(ISOStamp.format(now).prefix(10)).",
        ]

        func projectSection(_ p: Project, level: String) -> [String] {
            var lines = ["", "\(level) \(p.title.isEmpty ? "Untitled project" : p.title)"]
            let notes = p.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { lines.append(contentsOf: ["", notes]) }
            let mine = ordered(todos.filter { $0.projectId == p.id }, order: \.order, id: \.id)
            let loose = mine.filter { t in
                guard let hid = t.headingId else { return true }
                return e.headings[hid] == nil
            }
            if !loose.isEmpty {
                lines.append("")
                lines.append(contentsOf: loose.map(line))
            }
            let headings = ordered(
                e.headings.values.filter { $0.projectId == p.id }.map { $0 },
                order: \.order, id: \.id
            )
            for h in headings {
                let under = mine.filter { $0.headingId == h.id }
                lines.append("")
                lines.append("\(level)# \(h.title.isEmpty ? "Untitled heading" : h.title)")
                if !under.isEmpty {
                    lines.append("")
                    lines.append(contentsOf: under.map(line))
                }
            }
            return lines
        }

        let projects = ordered(
            live(Array(e.projects.values), trashed: \.trashedAt),
            order: \.order, id: \.id
        )
        let areas = ordered(
            live(Array(e.areas.values), trashed: \.trashedAt),
            order: \.order, id: \.id
        )
        for a in areas {
            parts.append("")
            parts.append("## \(a.title.isEmpty ? "Untitled area" : a.title)")
            let own = ordered(
                todos.filter { $0.areaId == a.id && $0.projectId == nil },
                order: \.order, id: \.id
            )
            if !own.isEmpty {
                parts.append("")
                parts.append(contentsOf: own.map(line))
            }
            for p in projects where p.areaId == a.id {
                parts.append(contentsOf: projectSection(p, level: "###"))
            }
        }
        for p in projects where p.areaId == nil || e.areas[p.areaId!] == nil {
            parts.append(contentsOf: projectSection(p, level: "##"))
        }
        let unfiled = ordered(
            todos.filter { $0.projectId == nil && $0.areaId == nil },
            order: \.order, id: \.id
        )
        if !unfiled.isEmpty {
            parts.append(contentsOf: ["", "## Not in a project or area", ""] + unfiled.map(line))
        }
        return parts.joined(separator: "\n") + "\n"
    }

    // MARK: - Import parse

    /// Accepts `dayrule-export` and `dayrule-things-export` (web `parseImport`).
    static func parseImport(_ text: String, today: LocalDate = When.toLocalDate(Date())) throws -> ExportData {
        if ThingsImport.looksLike(text) {
            return try ThingsImport.parseAndMap(text, today: today)
        }
        guard let data = text.data(using: .utf8),
              let rawAny = try? JSONSerialization.jsonObject(with: data),
              let raw = rawAny as? [String: Any]
        else {
            throw ImportError(message: "This file isn’t valid JSON.")
        }
        guard raw["format"] as? String == format else {
            throw ImportError(message: "This isn’t a Dayrule export.")
        }
        let versionNum = (raw["version"] as? Int)
            ?? (raw["version"] as? NSNumber)?.intValue
        guard versionNum == version else {
            let v = raw["version"].map { String(describing: $0) } ?? "?"
            throw ImportError(
                message: "This export is format version \(v); this app reads version \(version)."
            )
        }

        func list(_ key: String) throws -> [[String: Any]] {
            let v = raw[key] ?? []
            guard let arr = v as? [Any], arr.allSatisfy({ $0 is [String: Any] }) else {
                throw ImportError(message: "\"\(key)\" must be a list of records.")
            }
            if arr.count > 100_000 { throw ImportError(message: "Too many \(key).") }
            return arr.compactMap { $0 as? [String: Any] }
        }

        return ExportData(
            areas: try list("areas").enumerated().map { i, r in try parseArea(r, at: "Area \(i + 1)") },
            projects: try list("projects").enumerated().map { i, r in try parseProject(r, at: "Project \(i + 1)") },
            headings: try list("headings").enumerated().map { i, r in try parseHeading(r, at: "Heading \(i + 1)") },
            todos: try list("todos").enumerated().map { i, r in try parseTodo(r, at: "To-do \(i + 1)") },
            checklistItems: try list("checklistItems").enumerated().map { i, r in
                try parseChecklist(r, at: "Checklist item \(i + 1)")
            },
            tags: try list("tags").enumerated().map { i, r in try parseTag(r, at: "Tag \(i + 1)") }
        )
    }

    // MARK: - Parsers

    private static let dateRe = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
    private static let timeRe = try! NSRegularExpression(pattern: #"^([01]\d|2[0-3]):[0-5]\d$"#)
    private static let reminderRe = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d$"#
    )

    private static func stripClock(_ d: [String: Any]) -> [String: Any] {
        var d = d
        d.removeValue(forKey: "clock")
        return d
    }

    private static func req(_ r: [String: Any], _ k: String, _ at: String, max: Int = 100_000) throws -> String {
        guard let v = try str(r, k, at, optional: false, max: max) else {
            throw ImportError(message: "\(at): \"\(k)\" is missing.")
        }
        return v
    }

    private static func opt(_ r: [String: Any], _ k: String, _ at: String, max: Int = 200) throws -> String? {
        try str(r, k, at, optional: true, max: max)
    }

    private static func str(
        _ r: [String: Any],
        _ k: String,
        _ at: String,
        optional: Bool,
        max: Int
    ) throws -> String? {
        guard let v = r[k], !(v is NSNull) else {
            if optional { return nil }
            throw ImportError(message: "\(at): \"\(k)\" is missing.")
        }
        guard let s = v as? String else {
            throw ImportError(message: "\(at): \"\(k)\" must be text.")
        }
        if s.count > max {
            throw ImportError(message: "\(at): \"\(k)\" is too long.")
        }
        return s
    }

    private static func date(_ r: [String: Any], _ k: String, _ at: String) throws -> String? {
        guard let v = try opt(r, k, at) else { return nil }
        let range = NSRange(v.startIndex..<v.endIndex, in: v)
        guard dateRe.firstMatch(in: v, range: range) != nil else {
            throw ImportError(message: "\(at): \"\(k)\" must be a date like 2026-10-04.")
        }
        return v
    }

    private static func oneOf(
        _ r: [String: Any],
        _ k: String,
        _ at: String,
        _ allowed: [String],
        fallback: String? = nil
    ) throws -> String {
        let v = (r[k] as? String) ?? fallback
        guard let v, allowed.contains(v) else {
            throw ImportError(
                message: "\(at): \"\(k)\" must be one of \(allowed.joined(separator: ", "))."
            )
        }
        return v
    }

    private static func ids(_ r: [String: Any], _ k: String, _ at: String) throws -> [ID] {
        let v = r[k] ?? []
        guard let arr = v as? [Any], arr.allSatisfy({ $0 is String }) else {
            throw ImportError(message: "\(at): \"\(k)\" must be a list of ids.")
        }
        return arr.compactMap { $0 as? String }
    }

    private static func bool(_ r: [String: Any], _ k: String) -> Bool {
        r[k] as? Bool == true
    }

    private static func base(_ r: [String: Any], _ at: String) throws -> (id: ID, createdAt: Timestamp, updatedAt: Timestamp) {
        let now = ISOStamp.format(Date())
        return (
            try req(r, "id", at, max: 200),
            try opt(r, "createdAt", at) ?? now,
            try opt(r, "updatedAt", at) ?? now
        )
    }

    private static func parseArea(_ r: [String: Any], at: String) throws -> Area {
        let b = try base(r, at)
        return Area(
            id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, clock: nil,
            title: try req(r, "title", at),
            order: try req(r, "order", at, max: 200),
            tagIds: try ids(r, "tagIds", at),
            trashedAt: try opt(r, "trashedAt", at)
        )
    }

    private static func parseProject(_ r: [String: Any], at: String) throws -> Project {
        let b = try base(r, at)
        let status = try oneOf(r, "status", at, ["open", "completed", "canceled"])
        let start = try oneOf(r, "start", at, ["ready", "later"])
        return Project(
            id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, clock: nil,
            title: try req(r, "title", at),
            notes: try str(r, "notes", at, optional: true, max: 100_000) ?? "",
            areaId: try opt(r, "areaId", at),
            status: Status(rawValue: status)!,
            start: StartBucket(rawValue: start)!,
            startDate: try date(r, "startDate", at),
            tonight: bool(r, "tonight"),
            deadline: try date(r, "deadline", at),
            tagIds: try ids(r, "tagIds", at),
            order: try req(r, "order", at, max: 200),
            todayOrder: try opt(r, "todayOrder", at),
            completedAt: try opt(r, "completedAt", at),
            trashedAt: try opt(r, "trashedAt", at)
        )
    }

    private static func parseHeading(_ r: [String: Any], at: String) throws -> Heading {
        let b = try base(r, at)
        return Heading(
            id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, clock: nil,
            projectId: try req(r, "projectId", at, max: 200),
            title: try req(r, "title", at),
            order: try req(r, "order", at, max: 200),
            archived: bool(r, "archived")
        )
    }

    private static func parseTodo(_ r: [String: Any], at: String) throws -> Todo {
        let b = try base(r, at)
        let status = try oneOf(r, "status", at, ["open", "completed", "canceled"])
        let start = try oneOf(r, "start", at, ["inbox", "ready", "later"])
        return Todo(
            id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, clock: nil,
            title: try req(r, "title", at),
            notes: try str(r, "notes", at, optional: true, max: 100_000) ?? "",
            projectId: try opt(r, "projectId", at),
            headingId: try opt(r, "headingId", at),
            areaId: try opt(r, "areaId", at),
            status: Status(rawValue: status)!,
            start: StartBucket(rawValue: start)!,
            startDate: try date(r, "startDate", at),
            tonight: bool(r, "tonight"),
            deadline: try date(r, "deadline", at),
            tagIds: try ids(r, "tagIds", at),
            order: try req(r, "order", at, max: 200),
            todayOrder: try opt(r, "todayOrder", at),
            completedAt: try opt(r, "completedAt", at),
            trashedAt: try opt(r, "trashedAt", at),
            reminderAt: try parseReminderAt(r, at),
            repeat: try parseRepeat(r, at),
            repeatTemplateId: try opt(r, "repeatTemplateId", at)
        )
    }

    private static func parseChecklist(_ r: [String: Any], at: String) throws -> ChecklistItem {
        let b = try base(r, at)
        return ChecklistItem(
            id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, clock: nil,
            todoId: try req(r, "todoId", at, max: 200),
            title: try req(r, "title", at),
            done: bool(r, "done"),
            order: try req(r, "order", at, max: 200)
        )
    }

    private static func parseTag(_ r: [String: Any], at: String) throws -> Tag {
        let b = try base(r, at)
        return Tag(
            id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, clock: nil,
            title: try req(r, "title", at),
            parentId: try opt(r, "parentId", at),
            order: try req(r, "order", at, max: 200)
        )
    }

    private static func parseReminderAt(_ r: [String: Any], _ at: String) throws -> String? {
        guard let v = try opt(r, "reminderAt", at) else { return nil }
        let range = NSRange(v.startIndex..<v.endIndex, in: v)
        guard reminderRe.firstMatch(in: v, range: range) != nil else {
            throw ImportError(message: "\(at): \"reminderAt\" must look like 2026-10-04T09:00.")
        }
        return v
    }

    private static func parseRepeat(_ r: [String: Any], _ at: String) throws -> RepeatRule? {
        guard let v = r["repeat"], !(v is NSNull) else { return nil }
        guard let obj = v as? [String: Any] else {
            throw ImportError(message: "\(at): \"repeat\" must be a rule.")
        }
        let w = "\(at) repeat"
        let every: Int? = {
            if let i = obj["every"] as? Int { return i }
            if let n = obj["every"] as? NSNumber, n.doubleValue == n.doubleValue.rounded() {
                return n.intValue
            }
            return nil
        }()
        guard let every, (1...99).contains(every) else {
            throw ImportError(message: "\(w): \"every\" must be a whole number from 1 to 99.")
        }
        var weekdays: [Int]?
        if let wd = obj["weekdays"] {
            guard let arr = wd as? [Any] else {
                throw ImportError(message: "\(w): \"weekdays\" must be days 0 (Monday) to 6 (Sunday).")
            }
            var parsed: [Int] = []
            for x in arr {
                let n: Int?
                if let i = x as? Int { n = i }
                else if let num = x as? NSNumber { n = num.intValue }
                else { n = nil }
                guard let n, (0...6).contains(n) else {
                    throw ImportError(message: "\(w): \"weekdays\" must be days 0 (Monday) to 6 (Sunday).")
                }
                parsed.append(n)
            }
            weekdays = parsed
        }
        guard let anchor = try date(obj, "anchor", w) else {
            throw ImportError(message: "\(w): \"anchor\" is missing.")
        }
        if let reminderTime = try opt(obj, "reminderTime", w) {
            let range = NSRange(reminderTime.startIndex..<reminderTime.endIndex, in: reminderTime)
            guard timeRe.firstMatch(in: reminderTime, range: range) != nil else {
                throw ImportError(message: "\(w): \"reminderTime\" must look like 09:00.")
            }
        }
        let freq = try oneOf(obj, "freq", w, ["day", "week", "month", "year"])
        let mode = try oneOf(obj, "mode", w, ["fixed", "afterCompletion"])
        return RepeatRule(
            freq: RepeatRule.Freq(rawValue: freq)!,
            every: every,
            weekdays: weekdays,
            mode: RepeatRule.Mode(rawValue: mode)!,
            anchor: anchor,
            next: try date(obj, "next", w),
            reminderTime: try opt(obj, "reminderTime", w)
        )
    }
}

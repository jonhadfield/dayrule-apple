import Foundation

/// Overlay that records before/after for each touched entity (web `Draft`).
final class Draft {
    private let base: Entities
    private var touched: [String: StoreChange] = [:]
    private var settingsChange: StoreChange?

    init(base: Entities) {
        self.base = base
    }

    func getTodo(_ id: ID) -> Todo? {
        if case let .entity(_, _, _, after?, _) = touched["todos/\(id)"] {
            return EntityJSON.decodeTodo(JSONDict.toAny(after), id: id)
        }
        if case let .entity(_, _, _, nil, _) = touched["todos/\(id)"] {
            return nil
        }
        return base.todos[id]
    }

    func getProject(_ id: ID) -> Project? {
        if case let .entity(_, _, _, after?, _) = touched["projects/\(id)"] {
            return EntityJSON.decodeProject(JSONDict.toAny(after), id: id)
        }
        if case let .entity(_, _, _, nil, _) = touched["projects/\(id)"] {
            return nil
        }
        return base.projects[id]
    }

    func getArea(_ id: ID) -> Area? {
        if case let .entity(_, _, _, after?, _) = touched["areas/\(id)"] {
            return EntityJSON.decodeArea(JSONDict.toAny(after), id: id)
        }
        if case let .entity(_, _, _, nil, _) = touched["areas/\(id)"] {
            return nil
        }
        return base.areas[id]
    }

    func allTodos() -> [Todo] {
        all(collection: .todos, baseMap: base.todos) { EntityJSON.decodeTodo($0, id: $1) }
    }

    func allProjects() -> [Project] {
        all(collection: .projects, baseMap: base.projects) { EntityJSON.decodeProject($0, id: $1) }
    }

    func allChecklistItems() -> [ChecklistItem] {
        all(collection: .checklistItems, baseMap: base.checklistItems) {
            EntityJSON.decodeChecklist($0, id: $1)
        }
    }

    func putTodo(_ t: Todo) {
        record(.todos, id: t.id, after: JSONDict.fromAny(EntityJSON.encode(t)))
    }

    func putProject(_ p: Project) {
        record(.projects, id: p.id, after: JSONDict.fromAny(EntityJSON.encode(p)))
    }

    func putArea(_ a: Area) {
        record(.areas, id: a.id, after: JSONDict.fromAny(EntityJSON.encode(a)))
    }

    func putChecklistItem(_ c: ChecklistItem) {
        record(.checklistItems, id: c.id, after: JSONDict.fromAny(EntityJSON.encode(c)))
    }

    func remove(_ collection: CollectionName, id: ID) {
        record(collection, id: id, after: nil)
    }

    var settings: Settings {
        if case let .settings(_, after, _) = settingsChange {
            return EntityJSON.decodeSettings(JSONDict.toAny(after))
        }
        return base.settings
    }

    func setSettings(_ next: Settings) {
        let before: [String: JSONValue] = {
            if case let .settings(b, _, _) = settingsChange { return b }
            return settingsDict(base.settings)
        }()
        settingsChange = .settings(before: before, after: settingsDict(next), hlc: nil)
    }

    func changes() -> [StoreChange] {
        var out: [StoreChange] = []
        for c in touched.values {
            if case let .entity(_, _, before, after, _) = c, before == after { continue }
            out.append(c)
        }
        if let settingsChange { out.append(settingsChange) }
        return out
    }

    private func all<T>(
        collection: CollectionName,
        baseMap: [ID: T],
        decode: ([String: Any], ID) -> T
    ) -> [T] where T: Equatable {
        var map = baseMap
        for (key, change) in touched {
            guard case let .entity(col, id, _, after, _) = change, col == collection else { continue }
            if let after {
                map[id] = decode(JSONDict.toAny(after), id)
            } else {
                map.removeValue(forKey: id)
            }
            _ = key
        }
        return Array(map.values)
    }

    private func record(_ collection: CollectionName, id: ID, after: [String: JSONValue]?) {
        let key = "\(collection.rawValue)/\(id)"
        let before: [String: JSONValue]? = {
            if case let .entity(_, _, b, _, _) = touched[key] { return b }
            return currentDict(collection, id: id)
        }()
        touched[key] = .entity(collection: collection, id: id, before: before, after: after, hlc: nil)
    }

    private func currentDict(_ collection: CollectionName, id: ID) -> [String: JSONValue]? {
        switch collection {
        case .todos: base.todos[id].map { JSONDict.fromAny(EntityJSON.encode($0)) }
        case .projects: base.projects[id].map { JSONDict.fromAny(EntityJSON.encode($0)) }
        case .areas: base.areas[id].map { JSONDict.fromAny(EntityJSON.encode($0)) }
        case .checklistItems: base.checklistItems[id].map { JSONDict.fromAny(EntityJSON.encode($0)) }
        case .headings: nil
        case .tags: nil
        }
    }

    private func settingsDict(_ s: Settings) -> [String: JSONValue] {
        var d: [String: Any] = ["moveToDone": s.moveToDone.rawValue]
        if let c = s.clock { d["clock"] = c }
        if let t = s.lastMovedToDoneAt { d["lastMovedToDoneAt"] = t }
        for (k, v) in s.unknown { d[k] = v.toAny() }
        return JSONDict.fromAny(d)
    }
}

enum ApplyChanges {
    static func apply(_ base: Entities, _ changes: [StoreChange], direction: Direction) -> Entities {
        var next = base
        let ordered = direction == .forward ? changes : changes.reversed()
        for c in ordered {
            switch c {
            case let .settings(_, after, _) where direction == .forward:
                next.settings = EntityJSON.decodeSettings(JSONDict.toAny(after))
            case let .settings(before, _, _) where direction == .backward:
                next.settings = EntityJSON.decodeSettings(JSONDict.toAny(before))
            case let .entity(collection, id, before, after, _):
                let value = direction == .forward ? after : before
                applyEntity(&next, collection: collection, id: id, value: value)
            default:
                break
            }
        }
        return next
    }

    enum Direction { case forward, backward }

    private static func applyEntity(
        _ e: inout Entities,
        collection: CollectionName,
        id: ID,
        value: [String: JSONValue]?
    ) {
        switch collection {
        case .todos:
            if let value { e.todos[id] = EntityJSON.decodeTodo(JSONDict.toAny(value), id: id) }
            else { e.todos.removeValue(forKey: id) }
        case .projects:
            if let value { e.projects[id] = EntityJSON.decodeProject(JSONDict.toAny(value), id: id) }
            else { e.projects.removeValue(forKey: id) }
        case .areas:
            if let value { e.areas[id] = EntityJSON.decodeArea(JSONDict.toAny(value), id: id) }
            else { e.areas.removeValue(forKey: id) }
        case .headings:
            if let value { e.headings[id] = EntityJSON.decodeHeading(JSONDict.toAny(value), id: id) }
            else { e.headings.removeValue(forKey: id) }
        case .checklistItems:
            if let value { e.checklistItems[id] = EntityJSON.decodeChecklist(JSONDict.toAny(value), id: id) }
            else { e.checklistItems.removeValue(forKey: id) }
        case .tags:
            if let value { e.tags[id] = EntityJSON.decodeTag(JSONDict.toAny(value), id: id) }
            else { e.tags.removeValue(forKey: id) }
        }
    }
}

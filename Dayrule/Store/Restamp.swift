import Foundation

enum Restamp {
    static func sameValue(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
        a == b
    }

    /// Stamp each changed field with `tick` (web `store.ts` `stamp`).
    static func stamp(current: Entities, changes: [StoreChange], tick: String) -> [StoreChange] {
        changes.map { c in
            switch c {
            case let .settings(_, after, _):
                let cur = settingsDict(current.settings)
                let stamped = restamp(before: cur, after: after, tick: tick)
                return .settings(before: cur, after: stamped, hlc: tick)
            case let .entity(collection, id, _, after, _):
                let cur = currentDict(current, collection: collection, id: id)
                let stampedAfter = after.map { restamp(before: cur, after: $0, tick: tick) }
                return .entity(
                    collection: collection,
                    id: id,
                    before: cur,
                    after: stampedAfter,
                    hlc: tick
                )
            }
        }
    }

    static func invert(_ changes: [StoreChange]) -> [StoreChange] {
        changes.reversed().map { c in
            switch c {
            case let .settings(before, after, hlc):
                .settings(before: after, after: before, hlc: hlc)
            case let .entity(collection, id, before, after, hlc):
                .entity(collection: collection, id: id, before: after, after: before, hlc: hlc)
            }
        }
    }

    /// Field-partial replay onto current state (web `rebase`).
    static func rebase(current: Entities, changes: [StoreChange]) -> [StoreChange] {
        changes.map { c in
            switch c {
            case let .settings(before, after, hlc):
                let cur = settingsDict(current.settings)
                return .settings(before: before, after: onto(cur, from: before, to: after), hlc: hlc)
            case let .entity(collection, id, before, after, hlc):
                guard let cur = currentDict(current, collection: collection, id: id),
                      let before, let after
                else { return c }
                return .entity(
                    collection: collection,
                    id: id,
                    before: before,
                    after: onto(cur, from: before, to: after),
                    hlc: hlc
                )
            }
        }
    }

    private static func restamp(
        before: [String: JSONValue]?,
        after: [String: JSONValue],
        tick: String
    ) -> [String: JSONValue] {
        var clock: FieldClock = [:]
        if case let .object(o)? = before?["clock"] {
            for (k, v) in o {
                if case let .string(s) = v { clock[k] = s }
            }
        }
        var keys = Set(after.keys)
        if let before { keys.formUnion(before.keys) }
        keys.remove("clock")
        for k in keys {
            let a = after[k]
            let b = before?[k]
            if before == nil || !sameValue(a, b) {
                clock[k] = tick
            }
        }
        var out = after
        out["clock"] = .object(clock.mapValues { .string($0) })
        return out
    }

    private static func onto(
        _ cur: [String: JSONValue],
        from: [String: JSONValue],
        to: [String: JSONValue]
    ) -> [String: JSONValue] {
        var out = cur
        var keys = Set(from.keys).union(to.keys)
        keys.remove("clock")
        for k in keys {
            if sameValue(from[k], to[k]) { continue }
            if let v = to[k] { out[k] = v }
            else { out.removeValue(forKey: k) }
        }
        return out
    }

    private static func currentDict(
        _ e: Entities,
        collection: CollectionName,
        id: ID
    ) -> [String: JSONValue]? {
        switch collection {
        case .todos: e.todos[id].map { JSONDict.fromAny(EntityJSON.encode($0)) }
        case .projects: e.projects[id].map { JSONDict.fromAny(EntityJSON.encode($0)) }
        case .areas: e.areas[id].map { JSONDict.fromAny(EntityJSON.encode($0)) }
        case .headings: e.headings[id].map { JSONDict.fromAny(encodeHeading($0)) }
        case .checklistItems: e.checklistItems[id].map { JSONDict.fromAny(encodeChecklist($0)) }
        case .tags: e.tags[id].map { JSONDict.fromAny(encodeTag($0)) }
        }
    }

    private static func settingsDict(_ s: Settings) -> [String: JSONValue] {
        var d: [String: Any] = ["moveToDone": s.moveToDone.rawValue]
        if let c = s.clock { d["clock"] = c }
        if let t = s.lastMovedToDoneAt { d["lastMovedToDoneAt"] = t }
        for (k, v) in s.unknown { d[k] = v.toAny() }
        return JSONDict.fromAny(d)
    }

    private static func encodeHeading(_ h: Heading) -> [String: Any] {
        var d: [String: Any] = [
            "type": "heading", "id": h.id, "createdAt": h.createdAt, "updatedAt": h.updatedAt,
            "projectId": h.projectId, "title": h.title, "order": h.order, "archived": h.archived,
        ]
        if let c = h.clock { d["clock"] = c }
        for (k, v) in h.unknown { d[k] = v.toAny() }
        return d
    }

    private static func encodeChecklist(_ c: ChecklistItem) -> [String: Any] {
        var d: [String: Any] = [
            "type": "checklistItem", "id": c.id, "createdAt": c.createdAt, "updatedAt": c.updatedAt,
            "todoId": c.todoId, "title": c.title, "done": c.done, "order": c.order,
        ]
        if let clock = c.clock { d["clock"] = clock }
        for (k, v) in c.unknown { d[k] = v.toAny() }
        return d
    }

    private static func encodeTag(_ t: Tag) -> [String: Any] {
        var d: [String: Any] = [
            "type": "tag", "id": t.id, "createdAt": t.createdAt, "updatedAt": t.updatedAt,
            "title": t.title, "order": t.order,
        ]
        if let c = t.clock { d["clock"] = c }
        if let p = t.parentId { d["parentId"] = p }
        for (k, v) in t.unknown { d[k] = v.toAny() }
        return d
    }
}

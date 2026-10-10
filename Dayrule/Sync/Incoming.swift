import Foundation

/// Remote/tab records → store changes (web `sync/incoming.ts`).
enum Incoming {
    struct Item {
        var key: String
        var value: [String: Any]?
        var deleted: String?
    }

    static func parseKey(_ key: String) -> (collection: CollectionName, id: ID)? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let c = CollectionName(rawValue: parts[0]) else { return nil }
        return (c, parts[1])
    }

    static func allKeys(_ e: Entities) -> [String] {
        var keys = [CipherStore.settingsKey]
        for c in CipherStore.collections {
            for id in map(e, c).keys {
                keys.append("\(c.rawValue)/\(id)")
            }
        }
        return keys
    }

    static func lookup(_ e: Entities, key: String) -> [String: Any]? {
        if key == CipherStore.settingsKey { return settingsDict(e.settings) }
        guard let parsed = parseKey(key) else { return nil }
        return map(e, parsed.collection)[parsed.id]
    }

    static func incomingChanges(
        entities: Entities,
        items: [Item],
        localTombstones: [String: String] = [:]
    ) -> (changes: [StoreChange], pushBack: [String]) {
        var changes: [StoreChange] = []
        var pushBack = Set<String>()
        var seen: [String: [String: Any]?] = [:]

        func current(_ key: String) -> [String: Any]? {
            if seen.keys.contains(key) { return seen[key] ?? nil }
            return lookup(entities, key: key)
        }

        for item in items {
            if item.key == CipherStore.settingsKey {
                guard let remote = item.value else { continue }
                let local = current(item.key)
                let merged = Merge.mergeEntity(local: local, remote: remote)
                if !sameJSON(merged, local) {
                    changes.append(
                        .settings(
                            before: local.map(JSONDict.fromAny) ?? [:],
                            after: JSONDict.fromAny(merged),
                            hlc: nil
                        )
                    )
                }
                if !sameJSON(merged, remote) { pushBack.insert(item.key) }
                seen[item.key] = merged
                continue
            }
            guard let k = parseKey(item.key) else { continue }
            let local = current(item.key)

            if let deleted = item.deleted {
                guard let local else { continue }
                switch Merge.resolveTombstone(entity: local, tombstone: deleted) {
                case .keep:
                    pushBack.insert(item.key)
                case .delete:
                    changes.append(
                        .entity(
                            collection: k.collection,
                            id: k.id,
                            before: JSONDict.fromAny(local),
                            after: nil,
                            hlc: deleted
                        )
                    )
                    seen[item.key] = nil
                }
                continue
            }

            guard let value = item.value else { continue }
            if local == nil, let tomb = localTombstones[item.key] {
                let remoteLatest = Merge.latestStamp(value["clock"] as? FieldClock)
                if tomb >= remoteLatest {
                    pushBack.insert(item.key)
                    continue
                }
            }
            let merged = Merge.mergeEntity(local: local, remote: value)
            if !sameJSON(merged, local) {
                changes.append(
                    .entity(
                        collection: k.collection,
                        id: k.id,
                        before: local.map(JSONDict.fromAny),
                        after: JSONDict.fromAny(merged),
                        hlc: nil
                    )
                )
            }
            if !sameJSON(merged, value) { pushBack.insert(item.key) }
            seen[item.key] = merged
        }
        return (changes, Array(pushBack))
    }

    static func sameJSON(_ a: [String: Any]?, _ b: [String: Any]?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a?, b?):
            let da = try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys])
            let db = try? JSONSerialization.data(withJSONObject: b, options: [.sortedKeys])
            return da == db
        }
    }

    private static func map(_ e: Entities, _ c: CollectionName) -> [ID: [String: Any]] {
        switch c {
        case .todos: e.todos.mapValues { EntityJSON.encode($0) }
        case .projects: e.projects.mapValues { EntityJSON.encode($0) }
        case .areas: e.areas.mapValues { EntityJSON.encode($0) }
        case .headings:
            e.headings.mapValues { h in
                var d: [String: Any] = [
                    "type": "heading", "id": h.id, "createdAt": h.createdAt, "updatedAt": h.updatedAt,
                    "projectId": h.projectId, "title": h.title, "order": h.order, "archived": h.archived,
                ]
                if let clock = h.clock { d["clock"] = clock }
                for (k, v) in h.unknown { d[k] = v.toAny() }
                return d
            }
        case .checklistItems: e.checklistItems.mapValues { EntityJSON.encode($0) }
        case .tags:
            e.tags.mapValues { t in
                var d: [String: Any] = [
                    "type": "tag", "id": t.id, "createdAt": t.createdAt, "updatedAt": t.updatedAt,
                    "title": t.title, "order": t.order,
                ]
                if let clock = t.clock { d["clock"] = clock }
                if let p = t.parentId { d["parentId"] = p }
                for (k, v) in t.unknown { d[k] = v.toAny() }
                return d
            }
        }
    }

    private static func settingsDict(_ s: Settings) -> [String: Any] {
        var d: [String: Any] = ["moveToDone": s.moveToDone.rawValue]
        if let c = s.clock { d["clock"] = c }
        if let t = s.lastMovedToDoneAt { d["lastMovedToDoneAt"] = t }
        for (k, v) in s.unknown { d[k] = v.toAny() }
        return d
    }
}

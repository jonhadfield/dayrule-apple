import Foundation
import GRDB

/// GRDB ciphertext store + sync bookkeeping (web `persistence/encrypted.ts`).
actor CipherStore {
    static let settingsKey = "settings/settings"
    static let collections: [CollectionName] = [
        .areas, .projects, .headings, .todos, .checklistItems, .tags,
    ]

    private let dbQueue: DatabaseQueue
    private let cipher: any RecordCipher
    private var revCounter = 0

    init(dbQueue: DatabaseQueue, cipher: any RecordCipher) {
        self.dbQueue = dbQueue
        self.cipher = cipher
    }

    // MARK: - Entities

    func isEmpty() throws -> Bool {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM records") == 0
        }
    }

    func load() async throws -> Entities {
        let rows: [(id: String, env: EnvelopeB64)] = try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, alg, keyId, nonce, ciphertext FROM records").map { row in
                (
                    id: row["id"],
                    env: EnvelopeB64(
                        alg: row["alg"],
                        keyId: row["keyId"],
                        nonce: row["nonce"],
                        ciphertext: row["ciphertext"]
                    )
                )
            }
        }
        var e = Entities.empty()
        for row in rows {
            let plain = try await cipher.decrypt(recordId: row.id, envelope: row.env)
            let obj = try JSONSerialization.jsonObject(with: Data(plain)) as? [String: Any] ?? [:]
            if row.id == Self.settingsKey {
                e.settings = EntityJSON.decodeSettings(obj)
                continue
            }
            _ = EntityJSON.insert(key: row.id, value: obj, into: &e)
        }
        return e
    }

    /// Persist stamped local changes and enqueue them for push.
    func applyLocal(_ changes: [StoreChange]) async throws {
        try await apply(changes, enqueueOutbox: true)
    }

    /// Persist remote/tab changes without touching the outbox.
    func applyRemote(_ changes: [StoreChange]) async throws {
        try await apply(changes, enqueueOutbox: false)
    }

    func replaceAll(_ entities: Entities) async throws {
        var items: [(id: String, json: [UInt8])] = []
        let settingsJSON = try jsonUTF8(settingsDict(entities.settings))
        items.append((Self.settingsKey, settingsJSON))
        for collection in Self.collections {
            let dict = collectionMap(entities, collection)
            for (id, value) in dict {
                items.append(("\(collection.rawValue)/\(id)", try jsonUTF8(value)))
            }
        }
        var built: [(id: String, env: EnvelopeB64)] = []
        for item in items {
            let env = try await cipher.encrypt(recordId: item.id, jsonUTF8: item.json)
            built.append((item.id, env))
        }
        let rows = built
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM records")
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO records (id, alg, keyId, nonce, ciphertext)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [row.id, row.env.alg, row.env.keyId, row.env.nonce, row.env.ciphertext]
                )
            }
        }
    }

    // MARK: - Sync bookkeeping

    func outbox(limit: Int) throws -> [(key: String, rev: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT key, rev FROM outbox ORDER BY rev ASC LIMIT ?",
                arguments: [limit]
            ).map { (key: $0["key"], rev: $0["rev"]) }
        }
    }

    func markDirty(_ keys: [String]) throws {
        try dbQueue.write { db in
            for key in keys {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO outbox (key, rev) VALUES (?, ?)",
                    arguments: [key, nextRev()]
                )
            }
        }
    }

    func clearOutbox(_ done: [(key: String, rev: Int)]) throws {
        try dbQueue.write { db in
            for d in done {
                try db.execute(
                    sql: "DELETE FROM outbox WHERE key = ? AND rev = ?",
                    arguments: [d.key, d.rev]
                )
            }
        }
    }

    func setCursor(_ cursor: Int64) throws {
        try setState("cursor", value: cursor)
    }

    func cursor() throws -> Int64 {
        try getState("cursor") ?? 0
    }

    func setUploaded(_ uploaded: Bool) throws {
        try setState("uploaded", value: uploaded)
    }

    func uploaded() throws -> Bool {
        try getState("uploaded") ?? false
    }

    func pendingKeys() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT key FROM outbox")
        }
    }

    func seqs(_ keys: [String]) throws -> [String: Int64] {
        guard !keys.isEmpty else { return [:] }
        return try dbQueue.read { db in
            var out: [String: Int64] = [:]
            for key in keys {
                if let seq: Int64 = try Int64.fetchOne(
                    db, sql: "SELECT seq FROM syncmeta WHERE key = ?", arguments: [key]
                ) {
                    out[key] = seq
                }
            }
            return out
        }
    }

    func setSeqs(_ entries: [(key: String, seq: Int64)]) throws {
        try dbQueue.write { db in
            for e in entries {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO syncmeta (key, seq) VALUES (?, ?)",
                    arguments: [e.key, e.seq]
                )
            }
        }
    }

    func clearSeqs() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM syncmeta")
        }
    }

    func tombstone(_ key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT hlc FROM tombstones WHERE key = ?", arguments: [key])
        }
    }

    func tombstones(for keys: [String]) throws -> [String: String] {
        var out: [String: String] = [:]
        for key in keys {
            if let h = try tombstone(key) { out[key] = h }
        }
        return out
    }

    // MARK: - Private

    private func apply(_ changes: [StoreChange], enqueueOutbox: Bool) async throws {
        var puts: [(id: String, json: [UInt8])] = []
        var deletes: [String] = []
        var tombs: [(key: String, hlc: String)] = []
        for c in changes {
            switch c {
            case let .settings(_, after, _):
                puts.append((Self.settingsKey, try jsonUTF8(JSONDict.toAny(after))))
            case let .entity(collection, id, _, after, hlc):
                let key = "\(collection.rawValue)/\(id)"
                if let after {
                    puts.append((key, try jsonUTF8(JSONDict.toAny(after))))
                } else {
                    deletes.append(key)
                    tombs.append((key, hlc ?? ""))
                }
            }
        }
        var built: [(id: String, env: EnvelopeB64)] = []
        for p in puts {
            built.append((p.id, try await cipher.encrypt(recordId: p.id, jsonUTF8: p.json)))
        }
        let rows = built
        let deleteIds = deletes
        let tombRows = tombs
        let outboxEntries: [(String, Int)] = enqueueOutbox
            ? changes.map { (Self.keyOf($0), nextRev()) }
            : []
        try await dbQueue.write { db in
            for row in rows {
                try db.execute(
                    sql: """
                    INSERT INTO records (id, alg, keyId, nonce, ciphertext)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      alg = excluded.alg,
                      keyId = excluded.keyId,
                      nonce = excluded.nonce,
                      ciphertext = excluded.ciphertext
                    """,
                    arguments: [row.id, row.env.alg, row.env.keyId, row.env.nonce, row.env.ciphertext]
                )
                try db.execute(sql: "DELETE FROM tombstones WHERE key = ?", arguments: [row.id])
            }
            for id in deleteIds {
                try db.execute(sql: "DELETE FROM records WHERE id = ?", arguments: [id])
            }
            for t in tombRows {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO tombstones (key, hlc) VALUES (?, ?)",
                    arguments: [t.key, t.hlc]
                )
            }
            for (key, rev) in outboxEntries {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO outbox (key, rev) VALUES (?, ?)",
                    arguments: [key, rev]
                )
            }
        }
    }

    private func nextRev() -> Int {
        revCounter += 1
        return Int(Date().timeIntervalSince1970 * 1000) * 1000 + (revCounter % 1000)
    }

    private func getState<T: Decodable>(_ k: String) throws -> T? {
        try dbQueue.read { db in
            guard let json: String = try String.fetchOne(
                db, sql: "SELECT v FROM state WHERE k = ?", arguments: [k]
            ) else { return nil }
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
    }

    private func setState<T: Encodable>(_ k: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8)!
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO state (k, v) VALUES (?, ?)",
                arguments: [k, json]
            )
        }
    }

    private static func keyOf(_ c: StoreChange) -> String {
        switch c {
        case .settings: settingsKey
        case let .entity(collection, id, _, _, _): "\(collection.rawValue)/\(id)"
        }
    }

    private func jsonUTF8(_ obj: [String: Any]) throws -> [UInt8] {
        [UInt8](try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]))
    }

    private func settingsDict(_ s: Settings) -> [String: Any] {
        var d: [String: Any] = ["moveToDone": s.moveToDone.rawValue]
        if let c = s.clock { d["clock"] = c }
        if let t = s.lastMovedToDoneAt { d["lastMovedToDoneAt"] = t }
        for (k, v) in s.unknown { d[k] = v.toAny() }
        return d
    }

    private func collectionMap(_ e: Entities, _ c: CollectionName) -> [ID: [String: Any]] {
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
}

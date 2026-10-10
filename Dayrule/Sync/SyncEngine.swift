import Foundation

enum SyncBlockedError: Error, LocalizedError {
    case tooLarge
    case quota

    var errorDescription: String? {
        switch self {
        case .quota: "Your account is full, so new changes stay on this device."
        case .tooLarge: "A to-do is too large to sync. Shorten its notes."
        }
    }
}

/// Pull/merge/push cycle (web `sync/engine.ts`).
@MainActor
final class SyncEngine {
    private let store: EntityStore
    private let db: CipherStore
    private let crypto: CryptoActor
    private let api: APIClient
    private let pushBatch = 200

    init(store: EntityStore, db: CipherStore, crypto: CryptoActor, api: APIClient) {
        self.store = store
        self.db = db
        self.crypto = crypto
        self.api = api
    }

    func sync() async throws {
        if !(try await db.uploaded()) {
            try await db.markDirty(Incoming.allKeys(store.entities))
            try await db.setUploaded(true)
        }
        for _ in 0..<4 {
            try await pull()
            if !(try await push()) { return }
        }
    }

    private func pull() async throws {
        var cursor = try await db.cursor()
        let full = cursor == 0
        var seen = Set<String>()
        while true {
            let page: PullResponse
            do {
                page = try await api.pull(since: cursor, full: full)
            } catch let APIError.http(status, _, _) where status == 410 && cursor > 0 {
                try await db.clearSeqs()
                try await db.setCursor(0)
                return try await pull()
            }
            if !page.records.isEmpty {
                var payloads: [Incoming.Item] = []
                var keys: [String] = []
                for rec in page.records {
                    guard let p = try await crypto.decryptSyncPayload(rec) else { continue }
                    let expected = try await crypto.syncId(for: p.key)
                    guard expected == rec.id.lowercased() else {
                        throw CryptoError.openFailed
                    }
                    payloads.append(Incoming.Item(key: p.key, value: p.valueAny, deleted: p.deleted))
                    keys.append(p.key)
                }
                let tombs = try await db.tombstones(for: keys)
                let result = Incoming.incomingChanges(
                    entities: store.entities,
                    items: payloads,
                    localTombstones: tombs
                )
                store.applyRemote(result.changes)
                try await db.setSeqs(
                    zip(keys, page.records).map { (key: $0.0, seq: $0.1.seq ?? 0) }
                )
                if !result.pushBack.isEmpty {
                    try await db.markDirty(result.pushBack)
                }
                for k in keys { seen.insert(k) }
            }
            cursor = page.cursor
            try await db.setCursor(cursor)
            if !page.hasMore { break }
        }
        if full { try await prune(seen: seen) }
    }

    private func prune(seen: Set<String>) async throws {
        let pending = Set(try await db.pendingKeys())
        let gone = Incoming.allKeys(store.entities).filter {
            $0 != CipherStore.settingsKey && !seen.contains($0) && !pending.contains($0)
        }
        guard !gone.isEmpty else { return }
        let stamp = store.tick()
        let result = Incoming.incomingChanges(
            entities: store.entities,
            items: gone.map { Incoming.Item(key: $0, value: nil, deleted: stamp) }
        )
        store.applyRemote(result.changes)
    }

    /// Returns true if something conflicted (caller should pull again).
    private func push() async throws -> Bool {
        var conflicted = false
        while true {
            let batch = try await db.outbox(limit: pushBatch)
            if batch.isEmpty { return conflicted }
            let keys = batch.map(\.key)
            let seqs = try await db.seqs(keys)
            var wire: [PushWireRecord] = []
            var ids: [String] = []
            for key in keys {
                let valueAny = Incoming.lookup(store.entities, key: key)
                let value = valueAny.map(JSONDict.fromAny)
                let deleted: String? = value == nil
                    ? (try await db.tombstone(key) ?? store.tick())
                    : nil
                let (id, env) = try await crypto.encryptSyncPayload(
                    key: key,
                    value: value,
                    deleted: deleted
                )
                ids.append(id)
                wire.append(
                    PushWireRecord(
                        id: id,
                        baseSeq: seqs[key] ?? 0,
                        alg: env.alg,
                        keyId: env.keyId,
                        nonce: env.nonce,
                        ciphertext: env.ciphertext,
                        tombstone: value == nil
                    )
                )
            }
            let response = try await api.push(wire)
            let byId = Dictionary(uniqueKeysWithValues: response.results.map { ($0.id, $0) })
            var done: [(key: String, rev: Int)] = []
            var accepted: [(key: String, seq: Int64)] = []
            var blocked: SyncBlockedError?
            for (i, row) in batch.enumerated() {
                guard let r = byId[ids[i]] else { continue }
                if let err = r.error {
                    blocked = err == "quota" ? .quota : .tooLarge
                } else if r.conflict == true {
                    conflicted = true
                } else {
                    done.append(row)
                    accepted.append((row.key, r.seq))
                }
            }
            try await db.setSeqs(accepted)
            try await db.clearOutbox(done)
            if let blocked { throw blocked }
            if conflicted { return true }
        }
    }
}

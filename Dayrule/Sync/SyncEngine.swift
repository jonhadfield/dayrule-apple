import Foundation

enum SyncBlockedError: Error, LocalizedError, Equatable {
    case tooLarge
    case quota

    var errorDescription: String? {
        switch self {
        case .quota: "Your account is full, so new changes stay on this device."
        case .tooLarge: "A to-do is too large to sync. Shorten its notes."
        }
    }
}

/// MainActor `EntityStore` access from the sync actor (decision 72).
/// All store traffic goes through `MainActor.run` so list UI is not blocked by
/// pull/push crypto and network — only by brief merge applies.
private struct EntityStoreHandle: Sendable {
    private final class Box: @unchecked Sendable {
        let store: EntityStore
        init(_ store: EntityStore) { self.store = store }
    }

    private let box: Box

    init(_ store: EntityStore) {
        box = Box(store)
    }

    func entities() async -> Entities {
        let store = box.store
        return await MainActor.run { store.entities }
    }

    func applyRemote(_ changes: [StoreChange]) async {
        let store = box.store
        await MainActor.run { store.applyRemote(changes) }
    }

    func tick() async -> String {
        let store = box.store
        return await MainActor.run { store.tick() }
    }
}

/// Pull/merge/push cycle (web `sync/engine.ts`).
///
/// Own actor so decrypt / encrypt / transport / CipherStore work is not
/// scheduled on the UI executor. Entity merges still hop to MainActor
/// (decision 72).
actor SyncEngine {
    private let store: EntityStoreHandle
    private let db: CipherStore
    private let crypto: CryptoActor
    private let net: any SyncTransport
    private let pushBatch = 200

    /// Set when a pull sees `alg` we cannot decrypt.
    private(set) var sawUnknownAlg = false

    init(
        store: EntityStore,
        db: CipherStore,
        crypto: CryptoActor,
        net: any SyncTransport
    ) {
        self.store = EntityStoreHandle(store)
        self.db = db
        self.crypto = crypto
        self.net = net
    }

    init(store: EntityStore, db: CipherStore, crypto: CryptoActor, api: APIClient) {
        self.init(store: store, db: db, crypto: crypto, net: api)
    }

    /// Runs up to 4 pull/push rounds. Throws on quota / too-large / transport errors.
    func sync() async throws {
        sawUnknownAlg = try await db.needsUpgrade()
        if !(try await db.uploaded()) {
            let keys = Incoming.allKeys(await store.entities())
            try await db.markDirty(keys)
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
        var heldUnknownAlg = false
        while true {
            let page: PullResponse
            do {
                page = try await net.pull(since: cursor, full: full)
            } catch let APIError.http(status, _, _) where status == 410 && cursor > 0 {
                try await db.clearSeqs()
                try await db.setCursor(0)
                return try await pull()
            }
            if !page.records.isEmpty {
                var payloads: [Incoming.Item] = []
                var keys: [String] = []
                var seqEntries: [(key: String, seq: Int64)] = []
                for rec in page.records {
                    if rec.alg != CryptoConstants.alg {
                        try await db.holdOpaque(rec)
                        sawUnknownAlg = true
                        heldUnknownAlg = true
                        continue
                    }
                    guard let p = try await crypto.decryptSyncPayload(rec) else { continue }
                    let expected = try await crypto.syncId(for: p.key)
                    guard expected == rec.id.lowercased() else {
                        throw CryptoError.openFailed
                    }
                    payloads.append(Incoming.Item(key: p.key, value: p.valueAny, deleted: p.deleted))
                    keys.append(p.key)
                    seqEntries.append((p.key, rec.seq ?? 0))
                }
                if !payloads.isEmpty {
                    let tombs = try await db.tombstones(for: keys)
                    let entities = await store.entities()
                    let result = Incoming.incomingChanges(
                        entities: entities,
                        items: payloads,
                        localTombstones: tombs
                    )
                    await store.applyRemote(result.changes)
                    try await db.setSeqs(seqEntries)
                    if !result.pushBack.isEmpty {
                        try await db.markDirty(result.pushBack)
                    }
                    for k in keys { seen.insert(k) }
                }
            }
            cursor = page.cursor
            try await db.setCursor(cursor)
            if !page.hasMore { break }
        }
        // Unknown alg means membership is incomplete — do not plant tombstones
        // (PLAN §10.2: keep ciphertext, don't merge).
        if full, !heldUnknownAlg { try await prune(seen: seen) }
    }

    private func prune(seen: Set<String>) async throws {
        let pending = Set(try await db.pendingKeys())
        let entities = await store.entities()
        let gone = Incoming.allKeys(entities).filter {
            $0 != CipherStore.settingsKey && !seen.contains($0) && !pending.contains($0)
        }
        guard !gone.isEmpty else { return }
        let stamp = await store.tick()
        let result = Incoming.incomingChanges(
            entities: entities,
            items: gone.map { Incoming.Item(key: $0, value: nil, deleted: stamp) }
        )
        await store.applyRemote(result.changes)
    }

    /// Returns true if something conflicted (caller should pull again).
    private func push() async throws -> Bool {
        var conflicted = false
        while true {
            let batch = try await db.outbox(limit: pushBatch)
            if batch.isEmpty { return conflicted }
            let keys = batch.map(\.key)
            let seqs = try await db.seqs(keys)
            let entities = await store.entities()
            var wire: [PushWireRecord] = []
            var ids: [String] = []
            for key in keys {
                let valueAny = Incoming.lookup(entities, key: key)
                let value = valueAny.map(JSONDict.fromAny)
                let deleted: String?
                if value == nil {
                    if let existing = try await db.tombstone(key) {
                        deleted = existing
                    } else {
                        deleted = await store.tick()
                    }
                } else {
                    deleted = nil
                }
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
            let response = try await net.push(wire)
            // Server / client id casing must not leave rows stuck in the outbox.
            let byId = Dictionary(
                uniqueKeysWithValues: response.results.map { ($0.id.lowercased(), $0) }
            )
            var done: [(key: String, rev: Int)] = []
            var accepted: [(key: String, seq: Int64)] = []
            var blocked: SyncBlockedError?
            for (i, row) in batch.enumerated() {
                guard let r = byId[ids[i].lowercased()] else { continue }
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

import Foundation

struct VaultEntity: Identifiable, Hashable, Sendable {
    var id: String { key }
    var key: String
    var title: String
    var type: String
}

struct VaultSnapshot: Sendable {
    var entities: [VaultEntity]
    var counts: [String: Int]
    var recordCount: Int
    var skippedUnknownAlg: Int
}

enum VaultPull {
    /// Pull all sync records and decrypt titles (read-only M2 slice).
    static func pullAll(api: APIClient, crypto: CryptoActor) async throws -> VaultSnapshot {
        var since: Int64 = 0
        var records: [WireRecord] = []

        while true {
            // full=1 for every page of a download that started at zero.
            let pull = try await api.pull(since: since, full: true)
            records.append(contentsOf: pull.records)
            since = pull.cursor
            if !pull.hasMore { break }
        }

        return try await materialize(records: records, crypto: crypto)
    }

    /// Decrypt a page of wire records into entity titles/counts (testable without a network).
    static func materialize(records: [WireRecord], crypto: CryptoActor) async throws -> VaultSnapshot {
        var entities: [VaultEntity] = []
        var skipped = 0

        for rec in records {
            if rec.tombstone == true { continue }
            if rec.alg != CryptoConstants.alg {
                skipped += 1
                continue
            }
            do {
                if let entity = try await crypto.decryptSyncRecord(rec) {
                    entities.append(entity)
                }
            } catch {
                skipped += 1
            }
        }

        var counts: [String: Int] = [:]
        for e in entities {
            let collection = e.key.split(separator: "/").first.map(String.init) ?? "unknown"
            counts[collection, default: 0] += 1
        }
        entities.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return VaultSnapshot(
            entities: entities,
            counts: counts,
            recordCount: records.count,
            skippedUnknownAlg: skipped
        )
    }
}

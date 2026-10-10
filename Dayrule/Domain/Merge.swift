import Foundation

typealias FieldClock = [String: String]
typealias HlcStamp = String

/// Field-level LWW merge (web `domain/merge.ts`, PLAN §11.2).
enum Merge {
    private static let meta: Set<String> = ["clock"]

    static func latestStamp(_ clock: FieldClock?) -> HlcStamp {
        guard let values = clock?.values else { return "" }
        var max = ""
        for s in values where s > max {
            max = s
        }
        return max
    }

    /// Merge two JSON-shaped entity dictionaries (unknown fields preserved).
    static func mergeEntity(
        local: [String: Any]?,
        remote: [String: Any]
    ) -> [String: Any] {
        guard let local else { return remote }
        let lc = (local["clock"] as? FieldClock) ?? [:]
        let rc = (remote["clock"] as? FieldClock) ?? [:]
        var out: [String: Any] = [:]
        var clock: FieldClock = [:]
        var keys = Set(local.keys).union(remote.keys).union(lc.keys).union(rc.keys)
        keys.remove("clock")
        for k in keys {
            if meta.contains(k) { continue }
            let l = lc[k] ?? ""
            let r = rc[k] ?? ""
            let fromRemote = r > l
            let src = fromRemote ? remote : local
            if let v = src[k] {
                out[k] = v
            }
            let stamp = fromRemote ? r : l
            if !stamp.isEmpty { clock[k] = stamp }
        }
        out["clock"] = clock
        return out
    }

    enum Resolution {
        case keep([String: Any])
        case delete
    }

    static func resolveTombstone(entity: [String: Any]?, tombstone: HlcStamp) -> Resolution {
        guard let entity else { return .delete }
        let clock = entity["clock"] as? FieldClock
        return latestStamp(clock) > tombstone ? .keep(entity) : .delete
    }
}

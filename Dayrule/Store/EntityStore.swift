import Foundation

struct StoreClock: Sendable {
    var now: @Sendable () -> Date
    var newId: @Sendable () -> ID
    var hlc: HLC

    static func system(device: String = StoreClock.newDeviceId()) -> StoreClock {
        StoreClock(
            now: { Date() },
            newId: { UuidV7.generate() },
            hlc: HLC(device: device)
        )
    }

    static func newDeviceId() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<10).map { _ in alphabet.randomElement()! })
    }
}

/// Clock stamp for generated repeat instances (web `GENERATED`).
let generatedHlcStamp = "000000000-0000-generated"

/// In-memory entity store with HLC-stamped undoable commands (web `store.ts`).
@MainActor
final class EntityStore {
    private(set) var entities: Entities
    private(set) var past: [StoreEntry] = []
    private(set) var future: [StoreEntry] = []
    private let now: @Sendable () -> Date
    private let newId: @Sendable () -> ID
    private var hlc: HLC
    private let undoLimit = 200

    init(entities: Entities = .empty(), clock: StoreClock = .system()) {
        self.entities = entities
        self.now = clock.now
        self.newId = clock.newId
        self.hlc = clock.hlc
    }

    struct Env: Sendable {
        var now: Date
        var today: LocalDate
        var newId: @Sendable () -> ID
    }

    private func env() -> Env {
        let instant = now()
        return Env(now: instant, today: When.toLocalDate(instant), newId: newId)
    }

    @discardableResult
    func run<R>(_ label: String, _ command: (Draft, Env) throws -> R) rethrows -> R {
        let draft = Draft(base: entities)
        let result = try command(draft, env())
        let proposed = draft.changes()
        guard !proposed.isEmpty else { return result }
        let tick = hlc.tick()
        let stamped = Restamp.stamp(current: entities, changes: proposed, tick: tick)
        entities = ApplyChanges.apply(entities, stamped, direction: .forward)
        past.append(StoreEntry(label: label, changes: stamped))
        if past.count > undoLimit { past.removeFirst(past.count - undoLimit) }
        future.removeAll()
        return result
    }

    @discardableResult
    func undo() -> String? {
        guard let entry = past.popLast() else { return nil }
        let tick = hlc.tick()
        let changes = Restamp.stamp(
            current: entities,
            changes: Restamp.rebase(current: entities, changes: Restamp.invert(entry.changes)),
            tick: tick
        )
        entities = ApplyChanges.apply(entities, changes, direction: .forward)
        future.append(entry)
        return entry.label
    }

    @discardableResult
    func redo() -> String? {
        guard let entry = future.popLast() else { return nil }
        let tick = hlc.tick()
        let changes = Restamp.stamp(
            current: entities,
            changes: Restamp.rebase(current: entities, changes: entry.changes),
            tick: tick
        )
        entities = ApplyChanges.apply(entities, changes, direction: .forward)
        past.append(entry)
        return entry.label
    }

    func hydrate(_ entities: Entities) {
        self.entities = entities
        past.removeAll()
        future.removeAll()
    }

    /// Upkeep that isn't a user action (repeat instances): no undo entry;
    /// created records use `generatedHlcStamp` so devices converge.
    func generate(_ command: (Draft, Env) -> Set<String>) {
        let draft = Draft(base: entities)
        let created = command(draft, env())
        let proposed = draft.changes()
        guard !proposed.isEmpty else { return }
        let tick = hlc.tick()
        let stamped = Restamp.stamp(current: entities, changes: proposed, tick: tick).map { c -> StoreChange in
            guard case let .entity(collection, id, before, after, _) = c,
                  let after,
                  created.contains("\(collection.rawValue)/\(id)")
            else { return c }
            var fixed = after
            if case let .object(clock)? = after["clock"] {
                var gen: [String: JSONValue] = [:]
                for k in clock.keys { gen[k] = .string(generatedHlcStamp) }
                fixed["clock"] = .object(gen)
            }
            return .entity(
                collection: collection,
                id: id,
                before: before,
                after: fixed,
                hlc: generatedHlcStamp
            )
        }
        entities = ApplyChanges.apply(entities, stamped, direction: .forward)
    }

    func generateRepeats() {
        generate { d, env in Repeats.generateRepeats(d, env) }
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
}

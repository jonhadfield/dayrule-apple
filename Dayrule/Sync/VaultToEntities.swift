import Foundation

/// Best-effort Entities from the M2 read-only vault snapshot (titles only).
/// Full JSON decode with unknown-field preservation lands with the store port.
enum VaultToEntities {
    static func build(from vault: VaultSnapshot) -> Entities {
        var e = Entities.empty()
        var order: OrderKey = (try? Order.keyBetween(nil, nil)) ?? "a0"
        for entity in vault.entities {
            let parts = entity.key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let collection = parts[0]
            let id = parts[1]
            switch collection {
            case "todos":
                let t = Todo(
                    id: id,
                    createdAt: "1970-01-01T00:00:00.000Z",
                    updatedAt: "1970-01-01T00:00:00.000Z",
                    clock: nil,
                    title: entity.title,
                    notes: "",
                    projectId: nil,
                    headingId: nil,
                    areaId: nil,
                    status: .open,
                    start: .inbox,
                    startDate: nil,
                    tonight: false,
                    deadline: nil,
                    tagIds: [],
                    order: order,
                    todayOrder: nil,
                    completedAt: nil,
                    trashedAt: nil,
                    reminderAt: nil,
                    repeat: nil,
                    repeatTemplateId: nil
                )
                e.todos[id] = t
                order = (try? Order.keyBetween(order, nil)) ?? order
            case "projects":
                let p = Project(
                    id: id,
                    createdAt: "1970-01-01T00:00:00.000Z",
                    updatedAt: "1970-01-01T00:00:00.000Z",
                    clock: nil,
                    title: entity.title,
                    notes: "",
                    areaId: nil,
                    status: .open,
                    start: .ready,
                    startDate: nil,
                    tonight: false,
                    deadline: nil,
                    tagIds: [],
                    order: order,
                    todayOrder: nil,
                    completedAt: nil,
                    trashedAt: nil
                )
                e.projects[id] = p
                order = (try? Order.keyBetween(order, nil)) ?? order
            case "areas":
                let a = Area(
                    id: id,
                    createdAt: "1970-01-01T00:00:00.000Z",
                    updatedAt: "1970-01-01T00:00:00.000Z",
                    clock: nil,
                    title: entity.title,
                    order: order,
                    tagIds: [],
                    trashedAt: nil
                )
                e.areas[id] = a
                order = (try? Order.keyBetween(order, nil)) ?? order
            default:
                continue
            }
        }
        return e
    }
}

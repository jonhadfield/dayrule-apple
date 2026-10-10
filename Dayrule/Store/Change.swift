import Foundation

enum CollectionName: String, Sendable, CaseIterable {
    case areas, projects, headings, todos, checklistItems, tags
}

/// Recorded mutation for undo/redo (web `store/draft.ts` `Change`).
enum StoreChange: Sendable {
    case entity(
        collection: CollectionName,
        id: ID,
        before: [String: JSONValue]?,
        after: [String: JSONValue]?,
        hlc: String?
    )
    case settings(
        before: [String: JSONValue],
        after: [String: JSONValue],
        hlc: String?
    )

    var hlc: String? {
        switch self {
        case .entity(_, _, _, _, let hlc), .settings(_, _, let hlc): hlc
        }
    }
}

struct StoreEntry: Sendable {
    var label: String
    var changes: [StoreChange]
}

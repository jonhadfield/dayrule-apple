import Foundation

/// Pure helpers for list drag / VoiceOver reorder (web `arrayMove` + `commands.reorder`).
enum ListReorder {
    /// dnd-kit `arrayMove`: remove at `from`, insert at `to` on the shortened array.
    static func arrayMove<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), to >= 0, to <= items.count else { return items }
        var next = items
        let moved = next.remove(at: from)
        let insertAt = min(max(0, to), next.count)
        next.insert(moved, at: insertAt)
        return next
    }

    /// Neighbours after moving `id` onto `onto` within `peers` (drop-on-row).
    static func neighbours(
        peers: [ID],
        dragging id: ID,
        onto: ID
    ) -> (before: ID?, after: ID?)? {
        guard id != onto,
              let from = peers.firstIndex(of: id),
              let to = peers.firstIndex(of: onto)
        else { return nil }
        let moved = arrayMove(peers, from: from, to: to)
        guard let i = moved.firstIndex(of: id) else { return nil }
        return (
            before: i > 0 ? moved[i - 1] : nil,
            after: i + 1 < moved.count ? moved[i + 1] : nil
        )
    }

    /// Neighbours after a SwiftUI `onMove` of one index in `peers`.
    static func neighbours(
        peers: [ID],
        source: IndexSet,
        destination: Int
    ) -> (id: ID, before: ID?, after: ID?)? {
        guard let from = source.first, peers.indices.contains(from) else { return nil }
        let id = peers[from]
        var dest = destination
        if from < dest { dest -= 1 }
        let moved = arrayMove(peers, from: from, to: dest)
        guard let i = moved.firstIndex(of: id) else { return nil }
        return (
            id: id,
            before: i > 0 ? moved[i - 1] : nil,
            after: i + 1 < moved.count ? moved[i + 1] : nil
        )
    }

    /// Order field for a list surface (web `orderField`).
    static func orderField(for list: ListName) -> Commands.OrderField {
        list == .today ? .todayOrder : .order
    }

    /// Lists that support in-list drag reorder (not Done / Trash / Scheduled groups).
    static func allowsDrag(in list: ListName) -> Bool {
        switch list {
        case .inbox, .today, .backlog, .notNow:
            return true
        case .scheduled, .done, .trash:
            return false
        }
    }
}

import Foundation

/// Pure planning for local reminder notifications (PLAN §11).
enum ReminderPlan {
    static let maxPending = 64
    static let idPrefix = "dayrule.reminder."

    struct Entry: Equatable, Sendable {
        var todoId: ID
        var fireAt: String // YYYY-MM-DDTHH:mm
        var title: String
    }

    struct Request: Equatable, Sendable {
        var identifier: String
        var fireAt: String
        var body: String
    }

    /// Upcoming reminders from unlocked entities, nearest first, capped at 64.
    static func upcoming(
        _ e: Entities,
        now: Date = Date(),
        calendar: Calendar = When.calendar
    ) -> [Entry] {
        let nowLocal = localDateTime(now, calendar: calendar)
        var entries: [Entry] = []
        for t in e.todos.values {
            guard t.trashedAt == nil, let at = t.reminderAt, at >= nowLocal else { continue }
            entries.append(Entry(todoId: t.id, fireAt: at, title: t.title))
        }
        entries.sort {
            let c = Order.compareKeys($0.fireAt, $1.fireAt)
            if c != 0 { return c < 0 }
            return Order.compareKeys($0.todoId, $1.todoId) < 0
        }
        if entries.count > maxPending {
            entries = Array(entries.prefix(maxPending))
        }
        return entries
    }

    static func requests(
        from entries: [Entry],
        showTitles: Bool
    ) -> [Request] {
        entries.map { e in
            let time = String(e.fireAt.dropFirst(11).prefix(5))
            let body: String
            if showTitles, !e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body = e.title
            } else {
                body = "Reminder at \(time.isEmpty ? e.fireAt : time)"
            }
            return Request(
                identifier: "\(idPrefix)\(e.todoId)|\(e.fireAt)",
                fireAt: e.fireAt,
                body: body
            )
        }
    }

    /// Local `YYYY-MM-DDTHH:mm` in the given calendar.
    static func localDateTime(_ date: Date, calendar: Calendar = When.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0
        )
    }

    static func dateComponents(from fireAt: String) -> DateComponents? {
        let parts = fireAt.split(separator: "T")
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "-").compactMap { Int($0) }
        let t = parts[1].split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count >= 2 else { return nil }
        var c = DateComponents()
        c.year = d[0]
        c.month = d[1]
        c.day = d[2]
        c.hour = t[0]
        c.minute = t[1]
        c.second = 0
        return c
    }
}

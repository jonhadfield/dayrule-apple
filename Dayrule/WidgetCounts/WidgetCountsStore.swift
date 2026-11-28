import Foundation
import WidgetKit

/// Open-list counts for Home Screen / Lock Screen widgets (decision 76+).
/// Counts only — never titles or other decrypted content (PLAN §1).
enum WidgetCountsStore {
    /// Same App Group as Share → Inbox (`ShareInboxSupport.appGroupId`).
    static let appGroupId = "group.uk.co.lessknown.dayrule"

    private static let inboxKey = "widget.inboxOpen"
    private static let todayKey = "widget.todayOpen"
    private static let overdueKey = "widget.overdueOpen"
    private static let scheduledKey = "widget.scheduledOpen"
    private static let stampedKey = "widget.countsStampedAt"

    struct Snapshot: Equatable, Sendable {
        var inboxOpen: Int
        var todayOpen: Int
        /// Deadline-overdue items that also appear in Today (sidebar red badge).
        var overdueOpen: Int
        /// Open items waiting on a future When (Scheduled list).
        var scheduledOpen: Int
        /// When the main app last wrote counts (nil = never / cleared).
        var stampedAt: Date?
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func read() -> Snapshot {
        guard let defaults else {
            return Snapshot(
                inboxOpen: 0,
                todayOpen: 0,
                overdueOpen: 0,
                scheduledOpen: 0,
                stampedAt: nil
            )
        }
        let stamped: Date? = {
            let t = defaults.double(forKey: stampedKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }()
        return Snapshot(
            inboxOpen: max(0, defaults.integer(forKey: inboxKey)),
            todayOpen: max(0, defaults.integer(forKey: todayKey)),
            overdueOpen: max(0, defaults.integer(forKey: overdueKey)),
            scheduledOpen: max(0, defaults.integer(forKey: scheduledKey)),
            stampedAt: stamped
        )
    }

    /// Publish counts while unlocked. No-op when the App Group is missing.
    static func publish(
        inboxOpen: Int,
        todayOpen: Int,
        overdueOpen: Int = 0,
        scheduledOpen: Int = 0
    ) {
        guard let defaults else { return }
        defaults.set(max(0, inboxOpen), forKey: inboxKey)
        defaults.set(max(0, todayOpen), forKey: todayKey)
        defaults.set(max(0, overdueOpen), forKey: overdueKey)
        defaults.set(max(0, scheduledOpen), forKey: scheduledKey)
        defaults.set(Date().timeIntervalSince1970, forKey: stampedKey)
        reloadWidgets()
    }

    /// Drop cached counts on lock / sign-out so a locked device doesn’t show stale membership.
    static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: inboxKey)
        defaults.removeObject(forKey: todayKey)
        defaults.removeObject(forKey: overdueKey)
        defaults.removeObject(forKey: scheduledKey)
        defaults.removeObject(forKey: stampedKey)
        reloadWidgets()
    }

    private static func reloadWidgets() {
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: CountsWidgetKind.id)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayCountWidgetKind.id)
        WidgetCenter.shared.reloadTimelines(ofKind: InboxCountWidgetKind.id)
        #endif
    }
}

enum CountsWidgetKind {
    static let id = "DayruleCountsWidget"
}

enum TodayCountWidgetKind {
    static let id = "DayruleTodayCountWidget"
}

enum InboxCountWidgetKind {
    static let id = "DayruleInboxCountWidget"
}

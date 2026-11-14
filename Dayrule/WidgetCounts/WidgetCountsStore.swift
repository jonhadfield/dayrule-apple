import Foundation
import WidgetKit

/// Inbox / Today open counts for the Home Screen widget (decision 76).
/// Counts only — never titles or other decrypted content (PLAN §1).
enum WidgetCountsStore {
    /// Same App Group as Share → Inbox (`ShareInboxSupport.appGroupId`).
    static let appGroupId = "group.uk.co.lessknown.dayrule"

    private static let inboxKey = "widget.inboxOpen"
    private static let todayKey = "widget.todayOpen"
    private static let stampedKey = "widget.countsStampedAt"

    struct Snapshot: Equatable, Sendable {
        var inboxOpen: Int
        var todayOpen: Int
        /// When the main app last wrote counts (nil = never / cleared).
        var stampedAt: Date?
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func read() -> Snapshot {
        guard let defaults else {
            return Snapshot(inboxOpen: 0, todayOpen: 0, stampedAt: nil)
        }
        let stamped: Date? = {
            let t = defaults.double(forKey: stampedKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }()
        return Snapshot(
            inboxOpen: max(0, defaults.integer(forKey: inboxKey)),
            todayOpen: max(0, defaults.integer(forKey: todayKey)),
            stampedAt: stamped
        )
    }

    /// Publish counts while unlocked. No-op when the App Group is missing.
    static func publish(inboxOpen: Int, todayOpen: Int) {
        guard let defaults else { return }
        defaults.set(max(0, inboxOpen), forKey: inboxKey)
        defaults.set(max(0, todayOpen), forKey: todayKey)
        defaults.set(Date().timeIntervalSince1970, forKey: stampedKey)
        reloadWidgets()
    }

    /// Drop cached counts on lock / sign-out so a locked device doesn’t show stale membership.
    static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: inboxKey)
        defaults.removeObject(forKey: todayKey)
        defaults.removeObject(forKey: stampedKey)
        reloadWidgets()
    }

    private static func reloadWidgets() {
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: CountsWidgetKind.id)
        #endif
    }
}

enum CountsWidgetKind {
    static let id = "DayruleCountsWidget"
}

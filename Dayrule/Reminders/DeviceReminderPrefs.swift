import Foundation

/// Per-device reminder preferences (UserDefaults; PLAN §12).
enum DeviceReminderPrefs {
    private static let enabledKey = "dayrule.reminders.enabled"
    private static let showTitlesKey = "dayrule.reminders.showTitles"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// When true, notification body is the to-do title (OS stores it on device).
    static var showTitles: Bool {
        get { UserDefaults.standard.bool(forKey: showTitlesKey) }
        set { UserDefaults.standard.set(newValue, forKey: showTitlesKey) }
    }
}

import Foundation

/// Per-device unlock convenience prefs (UserDefaults; PLAN §8.2 / §12).
enum DeviceUnlockPrefs {
    private static let stayUnlockedKey = "dayrule.unlock.stayUnlocked"

    static var stayUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: stayUnlockedKey) }
        set { UserDefaults.standard.set(newValue, forKey: stayUnlockedKey) }
    }
}

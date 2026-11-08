#if os(iOS)
import UIKit

/// Home Screen quick actions (PLAN §1 Post-v1). Queues work until unlock —
/// never surfaces decrypted content on the lock screen.
@MainActor
enum QuickActions {
    static let newTodoType = "uk.co.lessknown.dayrule.new-todo"

    private static weak var model: AppModel?

    /// Shortcut that launched the process (cold start); drained on bind.
    private static var launchItem: UIApplicationShortcutItem?

    static func bind(_ model: AppModel) {
        self.model = model
        if let launchItem {
            self.launchItem = nil
            handle(launchItem)
        }
    }

    static func rememberLaunchOptions(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        launchItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem
    }

    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == newTodoType else { return false }
        if let model {
            model.requestFocusAdd()
        } else {
            // Warm-path race before bind: treat like a cold-start shortcut.
            launchItem = item
        }
        return true
    }
}
#endif

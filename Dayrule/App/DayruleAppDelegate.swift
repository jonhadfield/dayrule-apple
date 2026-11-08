#if os(iOS)
import UIKit

/// Refuses custom keyboard extensions so recovery words and passwords are not
/// delivered to a third-party keyboard with Full Access (PLAN §8.7).
/// UIKit’s hook is app-wide; there is no per-field API. Also receives Home
/// Screen quick actions (PLAN §1).
final class DayruleAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        QuickActions.rememberLaunchOptions(launchOptions)
        // false when launched from a shortcut so UIKit does not also call
        // performActionFor (would double-queue New to-do).
        if launchOptions?[.shortcutItem] != nil { return false }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActions.handle(shortcutItem))
    }

    func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
#endif

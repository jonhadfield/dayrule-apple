#if os(iOS)
import UIKit

/// Refuses custom keyboard extensions so recovery words and passwords are not
/// delivered to a third-party keyboard with Full Access (PLAN §8.7).
/// UIKit’s hook is app-wide; there is no per-field API.
final class DayruleAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
#endif

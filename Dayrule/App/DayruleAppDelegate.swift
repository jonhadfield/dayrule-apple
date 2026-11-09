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
#elseif os(macOS)
import AppKit

/// Mac chrome: quit when the last window closes (decision 55); dismiss sheets
/// before close (decision 56).
@MainActor
final class DayruleAppDelegate: NSObject, NSApplicationDelegate {
    private var closeProxies: [ObjectIdentifier: MacWindowDelegateProxy] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            installCloseGate(on: window)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyWindowChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func keyWindowChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        installCloseGate(on: window)
    }

    private func installCloseGate(on window: NSWindow) {
        // Panels / sheets get their own lifecycle; only titled app windows.
        guard window.styleMask.contains(.titled), window.styleMask.contains(.closable) else { return }
        let id = ObjectIdentifier(window)
        if let existing = closeProxies[id] {
            if window.delegate !== existing {
                existing.forward = window.delegate
                window.delegate = existing
            }
            return
        }
        if window.delegate is MacWindowDelegateProxy { return }
        let proxy = MacWindowDelegateProxy()
        proxy.forward = window.delegate
        closeProxies[id] = proxy
        window.delegate = proxy
    }
}
#endif

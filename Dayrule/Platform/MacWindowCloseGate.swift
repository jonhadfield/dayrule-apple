#if os(macOS)
import AppKit

/// Intercepts the red traffic-light / ⌘W close so open sheets dismiss first
/// (PLAN decision 56). Forwards other `NSWindowDelegate` calls to SwiftUI's delegate.
@MainActor
enum MacWindowCloseGate {
    static weak var model: AppModel?

    /// Clears Settings / Find / Help and asks the list shell to drop local sheets.
    /// Returns `true` when something was presented (caller must not close the window).
    static func dismissPresentedIfAny() -> Bool {
        model?.dismissPresentedChrome() ?? false
    }
}

/// Wraps the existing window delegate so SwiftUI keeps its behaviour.
final class MacWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var forward: (any NSWindowDelegate)?

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return true
        }
        return super.responds(to: aSelector) || (forward?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forward?.responds(to: aSelector) == true { return forward }
        return super.forwardingTarget(for: aSelector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let hadSheet = MainActor.assumeIsolated {
            MacWindowCloseGate.dismissPresentedIfAny()
        }
        if hadSheet { return false }
        return forward?.windowShouldClose?(sender) ?? true
    }
}
#endif

import SwiftUI

/// VoiceOver / Switch Control focus targets that sheets and covers must return to
/// on dismiss (ios-accessibility skill — focus restoration).
enum DayruleA11yFocus: Hashable, Sendable {
    case todo(ID)
    case find
    case settings
    case newList
    /// Project / area toolbar ellipsis (heading / move-project sheets).
    case detailActions
}

enum AccessibilityFocusRestore {
    /// Let the sheet/cover teardown finish before moving accessibility focus.
    static let dismissDelay: Duration = .milliseconds(100)

    @MainActor
    static func afterDismiss(_ apply: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: dismissDelay)
            guard !Task.isCancelled else { return }
            apply()
        }
    }
}

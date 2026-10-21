#if os(iOS)
import Testing
import UIKit
@testable import Dayrule

struct KeyboardExtensionTests {
    @Test("iOS refuses third-party keyboard extensions")
    @MainActor
    func refusesKeyboardExtensionPoint() {
        let delegate = DayruleAppDelegate()
        #expect(
            delegate.application(
                UIApplication.shared,
                shouldAllowExtensionPointIdentifier: .keyboard
            ) == false
        )
    }
}
#endif

import XCTest

final class DayruleUITests: XCTestCase {
    @MainActor
    func testLaunchShowsBrand() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Dayrule"].waitForExistence(timeout: 5))
    }

    /// Smoke audit on the locked gate (PLAN §14.1 M3).
    @MainActor
    func testGateAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Dayrule"].waitForExistence(timeout: 5))
        #if os(macOS)
        let window = app.windows.firstMatch.frame
        let touchBarFrames = Set(app.touchBars.firstMatch.descendants(matching: .any)
            .allElementsBoundByIndex.map { NSStringFromRect($0.frame) })
        try app.performAccessibilityAudit { issue in
            Self.isPlatformOwned(issue, window: window, touchBarFrames: touchBarFrames)
        }
        #else
        try app.performAccessibilityAudit()
        #endif
    }

    /// Unlocked Inbox audit via Debug empty vault (`DAYRULE_UI_TEST_UNLOCKED`).
    @MainActor
    func testUnlockedInboxAccessibilityAudit() throws {
        #if !DEBUG
        throw XCTSkip("DAYRULE_UI_TEST_UNLOCKED is Debug-only")
        #else
        let app = XCUIApplication()
        app.launchEnvironment["DAYRULE_MEMORY_KEYCHAIN"] = "1"
        app.launchEnvironment["DAYRULE_UI_TEST_UNLOCKED"] = "1"
        app.launch()

        let addField = app.textFields["list.addField"]
        let inbox = app.descendants(matching: .any)["list.sidebar.inbox"]
        XCTAssertTrue(
            addField.waitForExistence(timeout: 30) || inbox.waitForExistence(timeout: 30),
            "empty unlocked Inbox should appear"
        )

        #if os(macOS)
        let window = app.windows.firstMatch.frame
        let touchBarFrames = Set(app.touchBars.firstMatch.descendants(matching: .any)
            .allElementsBoundByIndex.map { NSStringFromRect($0.frame) })
        try app.performAccessibilityAudit { issue in
            Self.isPlatformOwned(issue, window: window, touchBarFrames: touchBarFrames)
        }
        #else
        // PLAN decision 66: ignore Dynamic Type / text-clipped false positives
        // from Fraunces + dense chrome until a dedicated large-text polish pass.
        // Smoke still catches contrast, hit region, traits, etc.
        try app.performAccessibilityAudit { issue in
            issue.auditType == .dynamicType || issue.auditType == .textClipped
        }
        #endif
        #endif
    }

    #if os(macOS)
    /// Issues macOS raises on elements that AppKit and SwiftUI own, not the app.
    /// Apple's own SwiftUI apps (Calculator, Passwords) fail the audit on the same
    /// elements. Everything inside the window's content is still audited.
    @MainActor
    private static func isPlatformOwned(
        _ issue: XCUIAccessibilityAuditIssue,
        window: CGRect,
        touchBarFrames: Set<String>
    ) -> Bool {
        guard let element = issue.element else {
            // Raised without an element whenever any SwiftUI text field has focus,
            // even one with no modifiers.
            return issue.auditType == .parentChild
        }
        switch element.elementType {
        case .touchBar:
            // SwiftUI's window controller always supplies a Touch Bar, even on
            // Macs without one.
            return true
        case .group where element.frame == window && element.label.isEmpty:
            // SwiftUI's hosting view: the unlabelled group that fills the window.
            return true
        default:
            // Touch Bar items a focused field adds (text suggestions).
            return touchBarFrames.contains(NSStringFromRect(element.frame))
        }
    }
    #endif
}

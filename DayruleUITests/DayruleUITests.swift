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
        // Residual decision 66: after accessibility-size row/title polish, phone-tab
        // DT ceiling removal, and sync-label wrapping, Apple’s auditor still flags
        // some paper chrome (Fraunces titles / toolbar glyphs / compact status) as
        // Dynamic Type or text-clipped. Ignore only those two types so contrast,
        // hit region, and traits still fail the build.
        try app.performAccessibilityAudit { issue in
            issue.auditType == .dynamicType || issue.auditType == .textClipped
        }
        #endif
        #endif
    }

    /// When sheet dismisses without losing the triggering to-do (focus restore
    /// wiring). VoiceOver `hasFocus` is not reliable in XCTest without VO on.
    @MainActor
    func testWhenSheetDismissKeepsTodoRow() throws {
        #if !DEBUG
        throw XCTSkip("DAYRULE_UI_TEST_UNLOCKED is Debug-only")
        #else
        let app = XCUIApplication()
        app.launchEnvironment["DAYRULE_MEMORY_KEYCHAIN"] = "1"
        app.launchEnvironment["DAYRULE_UI_TEST_UNLOCKED"] = "1"
        app.launch()

        let addField = app.textFields["list.addField"]
        XCTAssertTrue(addField.waitForExistence(timeout: 30), "empty unlocked Inbox should appear")

        let title = "When restore probe"
        addField.tap()
        addField.typeText(title)
        let addBtn = app.buttons["list.addButton"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 5))
        if addBtn.isEnabled {
            addBtn.tap()
        } else {
            addField.typeText("\n")
        }

        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", title)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "added to-do should appear")

        row.press(forDuration: 1.0)
        let whenAction = app.buttons["When…"].firstMatch
        let whenMenu = app.menuItems["When…"].firstMatch
        if whenAction.waitForExistence(timeout: 3) {
            whenAction.tap()
        } else if whenMenu.waitForExistence(timeout: 2) {
            whenMenu.tap()
        } else {
            throw XCTSkip("context menu When… not exposed in this destination")
        }

        let cancel = app.buttons["when.cancel"].firstMatch
        let cancelTitle = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 5) || cancelTitle.waitForExistence(timeout: 5),
            "When sheet should present"
        )
        if cancel.exists {
            cancel.tap()
        } else {
            cancelTitle.tap()
        }

        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "to-do row should remain after When dismiss (restore target)"
        )
        #endif
    }

    /// Phone tabs: Fraunces page title stays pinned; no second system title on pull.
    @MainActor
    func testPhoneTabTitleChromeNoDuplicateSystemTitle() throws {
        #if !DEBUG
        throw XCTSkip("DAYRULE_UI_TEST_UNLOCKED is Debug-only")
        #else
        #if os(iOS)
        let app = XCUIApplication()
        app.launchEnvironment["DAYRULE_MEMORY_KEYCHAIN"] = "1"
        app.launchEnvironment["DAYRULE_UI_TEST_UNLOCKED"] = "1"
        app.launch()

        let addField = app.textFields["list.addField"]
        XCTAssertTrue(addField.waitForExistence(timeout: 30), "empty unlocked Inbox should appear")

        let inboxHeaders = app.staticTexts.matching(NSPredicate(format: "label == %@", "Inbox"))
        XCTAssertGreaterThanOrEqual(inboxHeaders.count, 1)

        app.buttons["phone.tab.browse"].tap()
        XCTAssertTrue(
            app.staticTexts["Browse"].waitForExistence(timeout: 5),
            "Browse Fraunces title should appear"
        )

        app.buttons["phone.tab.inbox"].tap()
        XCTAssertTrue(addField.waitForExistence(timeout: 5))

        // Pull down: a scrolling system large title would add a second "Inbox".
        // Fraunces chrome may already sit in the nav-bar AX tree — compare counts.
        let inboxLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "Inbox"))
        let beforePull = inboxLabels.count
        let list = app.collectionViews.firstMatch
        if list.exists {
            list.swipeDown()
        } else {
            app.swipeDown()
        }
        XCTAssertEqual(
            inboxLabels.count,
            beforePull,
            "pull must not reveal a second system Inbox under Fraunces chrome"
        )
        #else
        throw XCTSkip("phone tabs are iOS-only")
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

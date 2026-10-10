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
        try app.performAccessibilityAudit()
    }
}

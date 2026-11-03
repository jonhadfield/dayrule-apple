import XCTest

/// Signs in on the iPhone Duo simulator and holds the unlocked vault while a
/// host script (`/tmp/duo-unlocked/READY` + hinge) captures Closed/Book/Open.
/// Skipped unless `/tmp/dayrule-duo-unlock.json` exists (not run in CI).
final class DuoUnlockedChromeTests: XCTestCase {
    private static let configURL = URL(fileURLWithPath: "/tmp/dayrule-duo-unlock.json")
    private static let readyURL = URL(fileURLWithPath: "/tmp/duo-unlocked/READY")
    private static let doneURL = URL(fileURLWithPath: "/tmp/duo-unlocked/DONE")

    private struct UnlockConfig: Decodable {
        var email: String
        var password: String
        var outDir: String
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: Self.configURL.path),
            "Missing /tmp/dayrule-duo-unlock.json"
        )
    }

    @MainActor
    private func isUnlocked(_ app: XCUIApplication) -> Bool {
        app.buttons["sidebar.find"].exists
            || app.buttons["phone.tab.today"].exists
            || app.buttons["phone.tab.inbox"].exists
            || app.buttons["ToggleSidebar"].exists
            || app.buttons["list.addButton"].exists
            || app.cells["list.sidebar.inbox"].exists
            || app.otherElements["list.sidebar.inbox"].exists
            || app.buttons["list.sidebar.inbox"].exists
    }

    @MainActor
    func testUnlockedChromeAcrossPoses() throws {
        let cfg = try JSONDecoder().decode(
            UnlockConfig.self,
            from: Data(contentsOf: Self.configURL)
        )
        try FileManager.default.createDirectory(
            atPath: cfg.outDir, withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: Self.readyURL)
        try? FileManager.default.removeItem(at: Self.doneURL)

        let app = XCUIApplication()
        app.launchEnvironment["DAYRULE_API"] = "https://dayrule.app"
        app.launch()

        let emailField = app.descendants(matching: .any)["gate.email"]
        let passwordField = app.descendants(matching: .any)["gate.password"]

        if isUnlocked(app) {
            // already in
        } else if emailField.waitForExistence(timeout: 25) {
            emailField.tap()
            if let v = emailField.value as? String, !v.isEmpty, v != "Email" {
                emailField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count))
            }
            emailField.typeText(cfg.email)
            passwordField.tap()
            passwordField.typeText(cfg.password)
            let stay = app.switches["gate.stayUnlocked"]
            if stay.exists, stay.value as? String != "1" {
                stay.tap()
            }
            app.buttons["gate.signIn"].tap()
        } else if passwordField.waitForExistence(timeout: 8) {
            passwordField.tap()
            passwordField.typeText(cfg.password)
            if app.buttons["gate.signIn"].exists {
                app.buttons["gate.signIn"].tap()
            } else if app.buttons["Unlock"].exists {
                app.buttons["Unlock"].tap()
            }
        } else {
            XCTFail("gate UI missing")
        }

        var ready = false
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if isUnlocked(app) {
                ready = true
                break
            }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertTrue(ready, "vault did not unlock")

        try "ready".write(to: Self.readyURL, atomically: true, encoding: .utf8)
        print("duo unlocked: READY written — host may hinge + screenshot")

        // Hold while a host script folds and captures (optional DONE).
        let holdUntil = Date().addingTimeInterval(60)
        while Date() < holdUntil {
            if FileManager.default.fileExists(atPath: Self.doneURL.path) {
                break
            }
            XCTAssertTrue(isUnlocked(app), "lost unlock chrome while holding for poses")
            Thread.sleep(forTimeInterval: 1)
        }
    }
}

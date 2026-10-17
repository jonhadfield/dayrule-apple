import XCTest

/// Captures App Store screenshots against production using the demo account.
/// Run only via `scripts/capture-app-store-screenshots.sh` (not in normal CI).
final class AppStoreScreenshotTests: XCTestCase {
    /// Written by `scripts/capture-app-store-screenshots.sh` (not env — xcodebuild
    /// does not forward arbitrary env into the XCTest process reliably).
    private static let configURL = URL(fileURLWithPath: "/tmp/dayrule-asc-capture.json")

    private struct CaptureConfig: Decodable {
        var email: String
        var password: String
        var outDir: String
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: Self.configURL.path),
            "Missing /tmp/dayrule-asc-capture.json — run scripts/capture-app-store-screenshots.sh"
        )
    }

    @MainActor
    private func sidebar(_ app: XCUIApplication, _ list: String) -> XCUIElement {
        let id = "list.sidebar.\(list)"
        let cell = app.cells[id]
        if cell.exists { return cell }
        let other = app.otherElements[id]
        if other.exists { return other }
        return app.buttons[id]
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

    /// iPad portrait collapses the split sidebar — open it so list ids exist.
    @MainActor
    private func ensureSidebarVisible(_ app: XCUIApplication) {
        if sidebar(app, "inbox").exists || sidebar(app, "today").exists { return }
        let toggle = app.buttons["ToggleSidebar"]
        if toggle.waitForExistence(timeout: 3) {
            toggle.tap()
            _ = sidebar(app, "today").waitForExistence(timeout: 5)
                || sidebar(app, "inbox").waitForExistence(timeout: 2)
        }
    }

    @MainActor
    private func dumpDebug(_ app: XCUIApplication, out: String, tag: String) {
        let dbg = (out as NSString).appendingPathComponent("debug-\(tag).txt")
        try? app.debugDescription.write(toFile: dbg, atomically: true, encoding: .utf8)
        let shot = windowPNG(app)
        try? shot.write(
            to: URL(fileURLWithPath: (out as NSString).appendingPathComponent("debug-\(tag).png"))
        )
    }

    /// Full screen on Simulator; the Dayrule window only on Mac (not the desktop).
    @MainActor
    private func windowPNG(_ app: XCUIApplication) -> Data {
        #if os(macOS)
        let window = app.windows.firstMatch
        if window.exists {
            return window.screenshot().pngRepresentation
        }
        #endif
        return XCUIScreen.main.screenshot().pngRepresentation
    }

    @MainActor
    func testCaptureScreenshots() throws {
        let cfg = try JSONDecoder().decode(
            CaptureConfig.self,
            from: Data(contentsOf: Self.configURL)
        )
        let email = cfg.email
        let password = cfg.password
        let out = cfg.outDir
        try FileManager.default.createDirectory(
            atPath: out, withIntermediateDirectories: true
        )

        let app = XCUIApplication()
        app.launchEnvironment["DAYRULE_API"] = "https://dayrule.app"
        app.launch()
        #if os(macOS)
        app.activate()
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
        #endif

        let todayTab = app.buttons["phone.tab.today"]
        let emailField = app.textFields["gate.email"]
        let passwordField = app.secureTextFields["gate.password"]

        if isUnlocked(app) {
            // continue
        } else if todayTab.waitForExistence(timeout: 3) || isUnlocked(app) {
            // continue
        } else if emailField.waitForExistence(timeout: 20) {
            emailField.tap()
            if let v = emailField.value as? String, !v.isEmpty, v != "Email" {
                let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count)
                emailField.typeText(clear)
            }
            emailField.typeText(email)
            passwordField.tap()
            passwordField.typeText(password)
            let stay = app.switches["gate.stayUnlocked"]
            if stay.exists, stay.value as? String != "1" {
                stay.tap()
            }
            app.buttons["gate.signIn"].tap()
        } else if passwordField.waitForExistence(timeout: 5) {
            passwordField.tap()
            passwordField.typeText(password)
            if app.buttons["gate.signIn"].exists {
                app.buttons["gate.signIn"].tap()
            } else if app.buttons["Unlock"].exists {
                app.buttons["Unlock"].tap()
            }
        } else {
            dumpDebug(app, out: out, tag: "no-gate")
            XCTFail("neither sign-in nor unlock UI appeared — see debug-no-gate.*")
        }

        // Cold first login = Argon2 + vault pull.
        Thread.sleep(forTimeInterval: 5)

        var ready = false
        let waitStart = Date()
        let deadline = waitStart.addingTimeInterval(180)
        while Date() < deadline {
            if isUnlocked(app) {
                ready = true
                break
            }
            if Date().timeIntervalSince(waitStart) > 30,
               emailField.exists,
               app.buttons["gate.signIn"].exists,
               app.buttons["gate.signIn"].isEnabled
            {
                dumpDebug(app, out: out, tag: "gate-stuck")
                break
            }
            Thread.sleep(forTimeInterval: 2)
        }
        if !ready {
            dumpDebug(app, out: out, tag: "fail")
        }
        XCTAssertTrue(ready, "lists did not appear after sign-in — see debug-fail.*")

        Thread.sleep(forTimeInterval: 3)

        let phone = todayTab.exists || app.buttons["phone.tab.inbox"].exists
        if !phone {
            #if os(iOS)
            // Portrait split view overlays the sidebar on the list; landscape
            // keeps a real double-column so App Store shots aren't clipped.
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 1.2)
            #endif
            ensureSidebarVisible(app)
        }

        func go(_ list: String) {
            if phone {
                let tab = app.buttons["phone.tab.\(list)"]
                if tab.waitForExistence(timeout: 3) {
                    tab.tap()
                    return
                }
            }
            ensureSidebarVisible(app)
            let side = sidebar(app, list)
            if side.waitForExistence(timeout: 5) {
                side.tap()
                return
            }
            let titles: [String: String] = [
                "today": "Today", "inbox": "Inbox", "scheduled": "Scheduled",
                "backlog": "Backlog", "done": "Done", "trash": "Trash",
            ]
            if let title = titles[list] {
                // Prefer sidebar row over detail title — match identifier first failed.
                let row = app.staticTexts[title]
                if row.waitForExistence(timeout: 2) {
                    row.tap()
                    return
                }
            }
            dumpDebug(app, out: out, tag: "nav-\(list)")
            XCTFail("could not navigate to \(list)")
        }

        func shot(_ name: String) {
            Thread.sleep(forTimeInterval: 0.6)
            let data = windowPNG(app)
            let path = (out as NSString).appendingPathComponent("\(name).png")
            do {
                try data.write(to: URL(fileURLWithPath: path))
                // iPad landscape: XCUIScreen still writes a portrait pixel buffer.
                // scripts/capture-app-store-screenshots.sh rotates with sips to
                // ASC size 2752×2064 after the test.
                print("screenshot: \(path)")
            } catch {
                XCTFail("write \(name): \(error)")
            }
        }

        func dismissKeyboard() {
            if app.keyboards.buttons["Hide keyboard"].waitForExistence(timeout: 1) {
                app.keyboards.buttons["Hide keyboard"].tap()
            } else if app.buttons["Hide keyboard"].exists {
                app.buttons["Hide keyboard"].tap()
            } else if app.keyboards.firstMatch.exists {
                // Tap the sheet title chrome to resign first responder.
                app.staticTexts["To-do"].tap()
            }
            Thread.sleep(forTimeInterval: 0.4)
        }

        go("today")
        shot("01-today")

        go("inbox")
        shot("02-inbox")

        go("scheduled")
        shot("03-scheduled")

        if phone {
            go("browse")
            Thread.sleep(forTimeInterval: 0.5)
            shot("04-browse")
            let kitchen = app.staticTexts["Kitchen"]
            if kitchen.waitForExistence(timeout: 10) {
                kitchen.tap()
                Thread.sleep(forTimeInterval: 1)
                shot("05-project-kitchen")
                let paint = app.staticTexts["Paint the cupboards"]
                if paint.waitForExistence(timeout: 5) {
                    paint.tap()
                    Thread.sleep(forTimeInterval: 1)
                    shot("06-editor-checklist")
                    if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
                    else if app.buttons["Save"].exists { app.buttons["Save"].tap() }
                    else { app.swipeDown() }
                }
            }
        } else {
            go("backlog")
            shot("04-backlog")
            ensureSidebarVisible(app)
            // Prefer sidebar project control — "Kitchen" also appears as a todo tag.
            let kitchenProject = app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label == %@",
                    "list.sidebar.project.",
                    "Kitchen"
                )
            ).firstMatch
            if kitchenProject.waitForExistence(timeout: 8) {
                kitchenProject.tap()
            } else {
                let anyProject = app.descendants(matching: .any).matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "list.sidebar.project.")
                ).firstMatch
                XCTAssertTrue(anyProject.waitForExistence(timeout: 3), "no sidebar project")
                anyProject.tap()
            }
            Thread.sleep(forTimeInterval: 1)
            shot("05-project-kitchen")
            // Row buttons often report hitPoint -1 in split view; tap the title label /
            // cell / absolute point instead.
            let paintTitle = app.staticTexts["Paint the cupboards"]
            XCTAssertTrue(paintTitle.waitForExistence(timeout: 8), "Paint todo missing")
            if paintTitle.isHittable {
                paintTitle.tap()
            } else {
                let cell = app.cells.containing(
                    NSPredicate(format: "label CONTAINS %@", "Paint the cupboards")
                ).firstMatch
                if cell.exists, cell.isHittable {
                    cell.tap()
                } else {
                    // Point inside the title (from a11y frame ~54,179 on 1032-wide).
                    app.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: 120, dy: 190))
                        .tap()
                }
            }
            let opened = app.textFields["editor.title"].waitForExistence(timeout: 6)
                || app.textViews["editor.title"].waitForExistence(timeout: 3)
                || app.buttons["editor.save"].waitForExistence(timeout: 3)
                || app.buttons["editor.checklist.add"].waitForExistence(timeout: 2)
            if !opened {
                dumpDebug(app, out: out, tag: "editor")
            }
            XCTAssertTrue(opened, "editor did not open — see debug-editor.*")
            dismissKeyboard()
            Thread.sleep(forTimeInterval: 0.5)
            shot("06-editor-checklist")
            if app.buttons["editor.save"].exists { app.buttons["editor.save"].tap() }
            else if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
            else if app.buttons["Save"].exists { app.buttons["Save"].tap() }
        }
    }
}

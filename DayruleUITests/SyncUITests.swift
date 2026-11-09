import Foundation
import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Local API signup + Add through the Gate/lists UI (PLAN §14.2).
/// Enabled by `/tmp/dayrule-e2e-config.json` from `scripts/local-sync-e2e.sh`
/// (script supplies a fresh `invite`; this test reads email codes from `api.log`).
final class SyncUITests: XCTestCase {
    @MainActor
    func testSignupAddTodoAppearsInInbox() throws {
        continueAfterFailure = false
        let cfgURL = URL(fileURLWithPath: "/tmp/dayrule-e2e-config.json")
        guard FileManager.default.fileExists(atPath: cfgURL.path),
              let data = try? Data(contentsOf: cfgURL),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              cfg["enabled"] == "1",
              let invite = cfg["invite"], !invite.isEmpty,
              let outDir = cfg["out"], !outDir.isEmpty
        else {
            throw XCTSkip("e2e config missing; run scripts/local-sync-e2e.sh")
        }

        let api = cfg["api"] ?? "http://127.0.0.1:8080"
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let email = "ui-e2e-\(stamp)@example.com"
        // No spaces: SecureField + software keyboard often drops them under XCTest.
        let password = "orangekettle99"
        let title = "UI marigold \(stamp)"
        let logPath = (outDir as NSString).appendingPathComponent("api.log")

        let app = XCUIApplication()
        app.launchEnvironment["DAYRULE_API"] = api
        // Unsigned UITest hosts hit Keychain -34018; process-local store for e2e only.
        app.launchEnvironment["DAYRULE_MEMORY_KEYCHAIN"] = "1"
        // Skip live HIBP range API during signup (PLAN decision 51).
        app.launchEnvironment["DAYRULE_HIBP_STUB"] = "1"
        app.launchEnvironment["DAYRULE_E2E"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["gate.createAccount"].waitForExistence(timeout: 10))
        app.buttons["gate.createAccount"].tap()

        // Prefill API from launch env; clear anyway so we don't append garbage.
        clearAndType(app.textFields["signup.api"], api)
        // Collapse Advanced so password fields aren't under the keyboard.
        let advanced = app.buttons["signup.api.advanced"]
        if advanced.waitForExistence(timeout: 2), (advanced.value as? String) == "Open" {
            advanced.tap()
        }
        clearAndType(app.textFields["signup.invite"], invite)
        clearAndType(app.textFields["signup.email"], email)

        app.buttons["signup.sendCode"].tap()
        // Fail fast if invite/API rejected.
        let err = app.staticTexts["signup.error"]
        if err.waitForExistence(timeout: 2) {
            XCTFail("signup/start failed: \(err.label)")
        }

        let code = try waitForEmailCode(email: email, logPath: logPath)
        clearAndType(app.textFields["signup.code"], code)
        let verifyBtn = app.buttons["signup.verifyCode"]
        verifyBtn.tap()

        // Don't trust isEnabled on SecureField; wait for verify to finish.
        let verifiedDeadline = Date().addingTimeInterval(20)
        while Date() < verifiedDeadline, verifyBtn.label != "Code verified" {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if err.exists { XCTFail("verify failed: \(err.label)") }
        }
        XCTAssertEqual(verifyBtn.label, "Code verified", "verify code before password")

        let passwordField = app.secureTextFields["signup.password"]
        pasteSecure(passwordField, password, in: app)
        let confirmField = app.secureTextFields["signup.confirmPassword"]
        pasteSecure(confirmField, password, in: app)
        tapWhenHittable(app.buttons["signup.continue"], in: app)

        // Surface derive/register errors instead of waiting out Argon2 timeout.
        if err.waitForExistence(timeout: 2) {
            XCTFail("signup continue failed: \(err.label)")
        }
        let phrase = app.staticTexts["Recovery phrase"]
        XCTAssertTrue(phrase.waitForExistence(timeout: 180), "recovery phrase after Argon2")
        let saved = app.descendants(matching: .any)["recovery.savedToggle"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        app.buttons["recovery.continue"].tap()

        // finishSignup pulls the vault before unlocking lists.
        let addField = app.textFields["list.addField"]
        XCTAssertTrue(addField.waitForExistence(timeout: 120), "inbox after register+pull")
        let inbox = app.descendants(matching: .any)["list.sidebar.inbox"]
        if inbox.waitForExistence(timeout: 3) { inbox.tap() }
        addField.tap()
        addField.typeText(title)
        let addBtn = app.buttons["list.addButton"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 5))
        let enableDeadline = Date().addingTimeInterval(5)
        while Date() < enableDeadline, !addBtn.isEnabled {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if addBtn.isEnabled {
            addBtn.tap()
        } else {
            addField.typeText("\n")
        }
        // Field clears when addTodo succeeds.
        let cleared = Date().addingTimeInterval(3)
        var fieldCleared = false
        while Date() < cleared {
            let v = addField.value as? String ?? ""
            if v.isEmpty || v == addField.placeholderValue {
                fieldCleared = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if !fieldCleared {
            addField.typeText("\n")
        }
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", title)
        ).firstMatch
        if !row.waitForExistence(timeout: 20) {
            let hierarchy = app.debugDescription
            XCTFail("todo \(title) in inbox; fieldCleared=\(fieldCleared); hierarchy=\(hierarchy)")
        }
    }

    @MainActor
    private func clearAndType(_ element: XCUIElement, _ text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        if let current = element.value as? String, !current.isEmpty,
           current != element.placeholderValue
        {
            // Wrapping (vertical-axis) fields put the caret where the tap lands;
            // a tap at the bottom-trailing corner puts it after the last character.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.9)).tap()
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4)
            element.typeText(deletes)
        }
        element.typeText(text)
        XCTAssertEqual(element.value as? String, text)
    }

    /// Paste into a SecureField. `typeText` often drops characters, which made
    /// password and confirm diverge when only one field fell back to typing.
    @MainActor
    private func pasteSecure(_ field: XCUIElement, _ text: String, in app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        for _ in 0..<3 {
            if !field.isHittable {
                app.swipeUp()
            }
            field.tap()
            dismissStrongPasswordIfNeeded(in: app)
            allowPasteIfAsked(in: app)
            field.press(forDuration: 1.2)
            let paste = app.menuItems["Paste"]
            if paste.waitForExistence(timeout: 2) {
                paste.tap()
                allowPasteIfAsked(in: app)
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                return
            }
            // Dismiss a half-open edit menu before retrying.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
        #endif
        XCTFail("could not paste into \(field.identifier)")
    }

    @MainActor
    private func dismissStrongPasswordIfNeeded(in app: XCUIApplication) {
        let chooseOwn = app.buttons["Choose My Own Password"]
        if chooseOwn.exists {
            chooseOwn.tap()
        }
    }

    @MainActor
    private func allowPasteIfAsked(in app: XCUIApplication) {
        let allow = app.alerts.buttons["Allow Paste"]
        if allow.exists {
            allow.tap()
        }
    }

    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, in app: XCUIApplication) {
        // Soft keyboard often covers Continue on compact iPhone simulators.
        if app.keyboards.element.exists {
            app.swipeUp()
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !element.isHittable {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func waitForEmailCode(email: String, logPath: String) throws -> String {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let text = try? String(contentsOfFile: logPath, encoding: .utf8) {
                for line in text.split(separator: "\n").reversed() {
                    guard line.contains("\"to\":\"\(email)\"") else { continue }
                    if let range = line.range(of: #"Your Dayrule code: (\d{6})"#, options: .regularExpression) {
                        let match = String(line[range])
                        if let code = match.split(separator: " ").last {
                            return String(code)
                        }
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("email code not logged for \(email)")
        return ""
    }
}

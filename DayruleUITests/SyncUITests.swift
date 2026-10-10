import Foundation
import XCTest

/// Local API signup + Add through the Gate/lists UI (PLAN §14.2).
/// Enabled by `/tmp/dayrule-e2e-config.json` from `scripts/local-sync-e2e.sh`
/// (script supplies a fresh `invite`; this test reads email codes from `api.log`).
final class SyncUITests: XCTestCase {
    @MainActor
    func testSignupAddTodoAppearsInInbox() throws {
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
        let password = "orange kettle drift"
        let title = "UI marigold \(stamp)"
        let logPath = (outDir as NSString).appendingPathComponent("api.log")

        let app = XCUIApplication()
        app.launchEnvironment["DAYRULE_API"] = api
        // Unsigned UITest hosts hit Keychain -34018; process-local store for e2e only.
        app.launchEnvironment["DAYRULE_MEMORY_KEYCHAIN"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["gate.createAccount"].waitForExistence(timeout: 10))
        app.buttons["gate.createAccount"].tap()

        // Prefill API from launch env; clear anyway so we don't append garbage.
        clearAndType(app.textFields["signup.api"], api)
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
        app.buttons["signup.verifyCode"].tap()

        let passwordField = app.secureTextFields["signup.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 10))
        // Don't trust isEnabled on SecureField; wait until Continue is tappable after verify.
        let continueBtn = app.buttons["signup.continue"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, continueBtn.label == "Continue", app.staticTexts["Code verified"].exists == false {
            // verify in flight
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if err.exists { XCTFail("verify failed: \(err.label)") }
        }
        passwordField.tap()
        passwordField.typeText(password)
        let confirmField = app.secureTextFields["signup.confirmPassword"]
        confirmField.tap()
        confirmField.typeText(password)
        continueBtn.tap()

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
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4)
            element.typeText(deletes)
        }
        element.typeText(text)
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

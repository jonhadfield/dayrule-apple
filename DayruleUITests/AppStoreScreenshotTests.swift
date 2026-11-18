import XCTest
#if os(macOS)
import AppKit
#endif

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
        let tree = app.debugDescription
        // Always print — Mac sandbox often blocks writes into the repo docs/ tree.
        print("debug hierarchy (\(tag), \(tree.count) chars):\n\(tree)")
        let tmpRoot = NSTemporaryDirectory()
        let dbgTmp = (tmpRoot as NSString).appendingPathComponent("dayrule-asc-debug-\(tag).txt")
        let pngTmp = (tmpRoot as NSString).appendingPathComponent("dayrule-asc-debug-\(tag).png")
        try? tree.write(toFile: dbgTmp, atomically: true, encoding: .utf8)
        let shot = windowPNG(app)
        try? shot.write(to: URL(fileURLWithPath: pngTmp))
        print("debug tmp: \(dbgTmp) / \(pngTmp)")
        let dbg = (out as NSString).appendingPathComponent("debug-\(tag).txt")
        let png = (out as NSString).appendingPathComponent("debug-\(tag).png")
        do {
            try tree.write(toFile: dbg, atomically: true, encoding: .utf8)
            try shot.write(to: URL(fileURLWithPath: png))
            print("debug also: \(dbg) / \(png)")
        } catch {
            print("debug outDir write skipped: \(error.localizedDescription)")
        }
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
        #if os(macOS)
        // Stuck Debug Dayrule (stay-unlocked / hung) makes launch()'s terminate
        // fail. Force-quit via AppKit before XCUIApplication.launch.
        for running in NSRunningApplication.runningApplications(
            withBundleIdentifier: "uk.co.lessknown.dayrule"
        ) {
            _ = running.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 1)
        #endif
        app.launch()
        #if os(macOS)
        app.activate()
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: 15)
        if window.exists { window.click() }
        // Cold launch may sit on the restoring privacy cover before the gate.
        let gateSignIn = app.buttons["gate.signIn"]
        let brand = app.staticTexts["Dayrule"]
        _ = gateSignIn.waitForExistence(timeout: 45)
            || brand.waitForExistence(timeout: 1)
            || isUnlocked(app)
        #endif

        let todayTab = app.buttons["phone.tab.today"]
        // Mac sometimes surfaces these as Any, not TextField.
        let emailField = app.descendants(matching: .any)["gate.email"]
        let passwordField = app.descendants(matching: .any)["gate.password"]

        if isUnlocked(app) {
            // continue
        } else if todayTab.waitForExistence(timeout: 3) || isUnlocked(app) {
            // continue
        } else if emailField.waitForExistence(timeout: 25) {
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
            } else if app.buttons["list.addDone"].waitForExistence(timeout: 0.5) {
                app.buttons["list.addDone"].tap()
            } else if app.keyboards.firstMatch.exists {
                // Resign without requiring a specific sheet title.
                if app.navigationBars.firstMatch.exists {
                    app.navigationBars.firstMatch.tap()
                } else {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }

        var capturedWhenShot = false

        /// Add sample titles via pinned/list Add when missing (agent vault for ASC).
        func seedMissing(_ titles: [String], dismissWhenSheet: Bool = false) {
            for title in titles {
                if app.staticTexts[title].waitForExistence(timeout: 0.4) { continue }
                // Exit multi-select / sheets left over from prior gestures.
                if app.buttons["Cancel"].waitForExistence(timeout: 0.3) {
                    app.buttons["Cancel"].tap()
                    Thread.sleep(forTimeInterval: 0.3)
                }
                dismissKeyboard()
                let field = app.textFields["list.addField"]
                guard field.waitForExistence(timeout: 4) else { continue }
                field.tap()
                // Wait for keyboard — typeText fails hard if focus never lands.
                guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { continue }
                field.typeText(title)
                let add = app.buttons["list.addButton"]
                if add.waitForExistence(timeout: 2), add.isEnabled {
                    add.tap()
                } else {
                    field.typeText("\n")
                }
                Thread.sleep(forTimeInterval: 0.5)
                if dismissWhenSheet {
                    // Scheduled Add opens When (already tomorrow). Capture once
                    // for ASC, then confirm Tomorrow.
                    if !capturedWhenShot,
                       app.buttons["Tomorrow"].waitForExistence(timeout: 2)
                    {
                        shot("07-when")
                        capturedWhenShot = true
                    }
                    let tomorrowChip = app.buttons["Tomorrow"]
                    if tomorrowChip.waitForExistence(timeout: 2) {
                        tomorrowChip.firstMatch.tap()
                        Thread.sleep(forTimeInterval: 0.4)
                    } else {
                        app.swipeDown()
                        Thread.sleep(forTimeInterval: 0.4)
                    }
                }
            }
            // Leave Add so shots aren’t keyboard-first.
            if app.buttons["list.addDone"].waitForExistence(timeout: 1) {
                app.buttons["list.addDone"].tap()
            }
            dismissKeyboard()
            // Tap the large title to clear any lingering keyboard chrome.
            if app.navigationBars.firstMatch.exists {
                app.navigationBars.firstMatch.tap()
            }
            Thread.sleep(forTimeInterval: 0.6)
        }

        func sidebarProject(named name: String) -> XCUIElement {
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label == %@",
                    "list.sidebar.project.",
                    name
                )
            ).firstMatch
        }

        func sidebarArea(named name: String) -> XCUIElement {
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label == %@",
                    "list.sidebar.area.",
                    name
                )
            ).firstMatch
        }

        /// Project or area sidebar row with this label (avoids duplicate creates).
        func sidebarNamed(_ name: String) -> XCUIElement {
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@) AND label == %@",
                    "list.sidebar.project.",
                    "list.sidebar.area.",
                    name
                )
            ).firstMatch
        }

        func openNewListMenu() {
            let newList = app.buttons["browse.newList"]
            guard newList.waitForExistence(timeout: 4) else { return }
            newList.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        /// Create a named project via New List when missing, then open it.
        @discardableResult
        func ensureProject(named name: String) -> Bool {
            if phone {
                go("browse")
            } else {
                ensureSidebarVisible(app)
            }
            // Prefer an existing sidebar row — never create a second Garden/Holidays.
            let existing = sidebarNamed(name)
            if existing.waitForExistence(timeout: 1.5) {
                existing.tap()
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
            // Browse list may show the title without a sidebar id (phone).
            if phone, app.staticTexts[name].waitForExistence(timeout: 1) {
                app.staticTexts[name].tap()
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
            openNewListMenu()
            let newProject = app.buttons["browse.newProject"]
            guard newProject.waitForExistence(timeout: 3) else { return false }
            newProject.tap()
            Thread.sleep(forTimeInterval: 0.8)
            let titleField = app.textFields["project.title"]
            guard titleField.waitForExistence(timeout: 4) else { return false }
            titleField.tap()
            // Clear placeholder "New Project" if selected.
            titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
            titleField.typeText(name)
            dismissKeyboard()
            Thread.sleep(forTimeInterval: 0.4)
            // Stay on the new project so the caller can seed todos.
            return true
        }

        /// Pop project/area detail back to Browse / sidebar root.
        func leaveDetailToBrowse() {
            dismissKeyboard()
            if phone {
                // Prefer the Browse tab over Back — title fields steal Back focus.
                let browseTab = app.buttons["phone.tab.browse"]
                if browseTab.waitForExistence(timeout: 2) {
                    browseTab.tap()
                    Thread.sleep(forTimeInterval: 0.4)
                    return
                }
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.waitForExistence(timeout: 1), back.isHittable {
                back.tap()
                Thread.sleep(forTimeInterval: 0.4)
            }
        }

        func ensureArea(named name: String) {
            if phone {
                go("browse")
            } else {
                ensureSidebarVisible(app)
            }
            // Sidebar id only — bare staticTexts[name] matched todos and skipped
            // creating the area, or matched the wrong surface and still duplicated.
            let areaRow = sidebarArea(named: name)
            if areaRow.waitForExistence(timeout: 1.5) {
                leaveDetailToBrowse()
                return
            }
            if phone, app.staticTexts[name].waitForExistence(timeout: 1) {
                leaveDetailToBrowse()
                return
            }
            openNewListMenu()
            let newArea = app.buttons["browse.newArea"]
            guard newArea.waitForExistence(timeout: 3) else { return }
            newArea.tap()
            Thread.sleep(forTimeInterval: 0.8)
            let titleField = app.textFields["area.title"]
            guard titleField.waitForExistence(timeout: 4) else { return }
            titleField.tap()
            titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
            titleField.typeText(name)
            dismissKeyboard()
            Thread.sleep(forTimeInterval: 0.4)
            leaveDetailToBrowse()
        }

        /// Add loose project todos via the pinned project Add field.
        func seedProjectTodos(_ titles: [String]) {
            let projectAdd = app.textFields["project.addField"]
            guard projectAdd.waitForExistence(timeout: 4) else { return }
            for title in titles {
                if app.staticTexts[title].waitForExistence(timeout: 0.3) { continue }
                projectAdd.tap()
                guard app.keyboards.firstMatch.waitForExistence(timeout: 2) else { continue }
                projectAdd.typeText(title)
                let addBtn = app.buttons["project.addButton"]
                if addBtn.waitForExistence(timeout: 1), addBtn.isEnabled {
                    addBtn.tap()
                } else {
                    projectAdd.typeText("\n")
                }
                Thread.sleep(forTimeInterval: 0.35)
            }
            dismissKeyboard()
        }

        /// House / Kitchen / Garden / Holidays — denser Browse + sidebar for ASC.
        func ensureDemoOrganisation() {
            ensureArea(named: "House")
            _ = ensureProject(named: "Kitchen")
            seedProjectTodos([
                "Paint the cupboards",
                "Replace the tap washer",
                "Reorganise the pantry",
                "Buy new tea towels",
                "Descale the kettle",
                "Oil the chopping boards",
            ])
            _ = ensureProject(named: "Garden")
            seedProjectTodos([
                "Sow the sweet peas",
                "Mend the fence panel",
                "Order compost",
                "Sharpen the shears",
                "Plant the spring bulbs",
            ])
            _ = ensureProject(named: "Holidays")
            seedProjectTodos([
                "Book the cottage",
                "Pack the walking boots",
                "Check passport dates",
                "Arrange pet sitting",
            ])
            // Leave on Kitchen for the project shot that follows.
            _ = ensureProject(named: "Kitchen")
        }

        func openPaintEditor() {
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
            // Prefer a short, finished checklist — skip if Paint already has items.
            let hasChecklist = app.staticTexts["Sand the doors"].waitForExistence(timeout: 0.4)
                || app.staticTexts["Undercoat"].waitForExistence(timeout: 0.2)
            if !hasChecklist {
                let checklistAdd = app.buttons["editor.checklist.add"]
                for item in ["Sand the doors", "Undercoat", "Top coat"] {
                    guard checklistAdd.waitForExistence(timeout: 2) else { break }
                    checklistAdd.tap()
                    Thread.sleep(forTimeInterval: 0.25)
                    let fields = app.textFields
                    let count = fields.count
                    guard count > 0 else { continue }
                    let last = fields.element(boundBy: count - 1)
                    if last.waitForExistence(timeout: 1) {
                        last.tap()
                        last.typeText(item)
                    }
                    Thread.sleep(forTimeInterval: 0.25)
                }
            }
            dismissKeyboard()
            Thread.sleep(forTimeInterval: 0.4)
        }

        func closeEditor() {
            if app.buttons["editor.save"].exists { app.buttons["editor.save"].tap() }
            else if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
            else if app.buttons["Save"].exists { app.buttons["Save"].tap() }
            else { app.swipeDown() }
            Thread.sleep(forTimeInterval: 0.4)
        }

        // Fatten sparse agent lists so ASC shots aren’t empty paper.
        go("today")
        seedMissing([
            "Review today's list",
            "Walk for twenty minutes",
            "Reply to the school email",
            "Pick up dry cleaning",
            "Book dentist check-up",
            "Water the plants",
            "Prep tomorrow's lunch",
            "Call the plumber back",
            "Put the bins out",
            "Pack the swimming bag",
            "Confirm Friday babysitter",
            "Defrost the freezer drawer",
        ])
        shot("01-today")

        go("inbox")
        seedMissing([
            "Welcome — try completing this",
            "Read the library holds email",
            "Sort the recycling",
            "Draft weekend plan",
            "Return the borrowed book",
            "Check the boiler pressure",
            "Order dishwasher tablets",
            "Email the landlord about the leak",
            "Sharpen the kitchen knives",
            "Renew the parking permit",
            "Photograph the meter reading",
            "Write thank-you notes",
            "Label the spare keys",
        ])
        shot("02-inbox")

        go("scheduled")
        // Unique title forces a When sheet so we can capture 07-when even when
        // the rest of the Scheduled list is already seeded.
        let whenProbe = "Weekend market \(Int(Date().timeIntervalSince1970) % 100_000)"
        seedMissing([
            whenProbe,
            "Museum with the kids",
            "MOT appointment",
            "Garden centre run",
            "Softball practice",
            "Parents' evening",
            "Roofers' quote visit",
            "Blood test at the GP",
        ], dismissWhenSheet: true)
        shot("03-scheduled")

        // Projects + area first so Browse / sidebar shots look lived-in.
        ensureDemoOrganisation()

        // Push dense seed so Mac agent capture / other devices see the same vault.
        if app.buttons["Settings"].waitForExistence(timeout: 2) {
            app.buttons["Settings"].tap()
        } else if app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings")).firstMatch.exists {
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings")).firstMatch.tap()
        }
        if app.buttons["settings.syncNow"].waitForExistence(timeout: 4) {
            app.buttons["settings.syncNow"].tap()
            Thread.sleep(forTimeInterval: 5)
        }
        if app.buttons["Close"].waitForExistence(timeout: 1) {
            app.buttons["Close"].tap()
        } else if app.buttons["Done"].waitForExistence(timeout: 1) {
            app.buttons["Done"].tap()
        } else {
            app.swipeDown()
        }
        Thread.sleep(forTimeInterval: 0.5)

        if phone {
            go("browse")
            Thread.sleep(forTimeInterval: 0.6)
            shot("04-browse")
            _ = ensureProject(named: "Kitchen")
            shot("05-project-kitchen")
            openPaintEditor()
            shot("06-editor-checklist")
            closeEditor()
        } else {
            go("backlog")
            seedMissing([
                "Plan spring planting",
                "Replace hallway bulbs",
                "Catalogue the vinyl",
                "Research heat pump quotes",
                "Frame the beach photos",
                "Service the bike",
                "Clear the loft hatch",
                "Sort the tool drawer",
                "Wash the spare duvet",
            ])
            shot("04-backlog")
            // Sidebar should now list Kitchen / Garden / Holidays.
            ensureSidebarVisible(app)
            _ = ensureProject(named: "Kitchen")
            shot("05-project-kitchen")
            openPaintEditor()
            shot("06-editor-checklist")
            closeEditor()
        }

        // Quick Find overlay (toolbar magnifying glass on phone / sidebar on split).
        let findBtn: XCUIElement = {
            if app.buttons["list.find"].exists { return app.buttons["list.find"] }
            if app.buttons["sidebar.find"].exists { return app.buttons["sidebar.find"] }
            return app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Find")).firstMatch
        }()
        if findBtn.waitForExistence(timeout: 4) {
            findBtn.tap()
            let findField = app.textFields["find.field"]
            if findField.waitForExistence(timeout: 3) {
                findField.tap()
                _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
                findField.typeText("paint")
                Thread.sleep(forTimeInterval: 0.9)
                shot("08-find")
                if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
                else { app.swipeDown() }
            }
        }
    }
}

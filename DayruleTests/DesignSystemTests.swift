import CoreText
import Foundation
import SwiftUI
import Testing
@testable import Dayrule
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Design-system guards (PLAN §6.1, §6.2, §6.4): token contrast, the bundled
/// Fraunces instance, token hygiene, human dates and the completion linger.
@Suite("Design system")
struct DesignSystemTests {
    // MARK: Contrast (port of web `styles/contrast.test.ts`)

    private struct RGB {
        var r: Double
        var g: Double
        var b: Double

        init(_ c: Color) {
            let resolved = c.resolve(in: EnvironmentValues())
            r = Double(resolved.red)
            g = Double(resolved.green)
            b = Double(resolved.blue)
        }

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// WCAG relative luminance of a gamma-encoded sRGB colour.
        var luminance: Double {
            func lin(_ c: Double) -> Double {
                c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }

        /// `top` at `alpha` over `self`, for the translucent tints (web `mix`).
        func under(_ top: RGB, alpha: Double) -> RGB {
            RGB(
                r: top.r * alpha + r * (1 - alpha),
                g: top.g * alpha + g * (1 - alpha),
                b: top.b * alpha + b * (1 - alpha)
            )
        }
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test("text colours reach 4.5:1 on every background", arguments: [ColorScheme.light, .dark])
    func textContrast(scheme: ColorScheme) {
        let c = DayruleColors.resolve(colorScheme: scheme)
        let bg = RGB(c.bg)
        // Paper, sidebar, a selected row (accent at 10%) and a pressed row (sidebar at 60%).
        let backgrounds: [(String, RGB)] = [
            ("bg", bg),
            ("sidebar", RGB(c.sidebar)),
            ("selected", bg.under(RGB(c.accent), alpha: 0.10)),
            ("pressed", bg.under(RGB(c.sidebar), alpha: 0.6)),
        ]
        let text: [(String, Color)] = [
            ("text", c.text),
            ("textSecondary", c.textSecondary),
            ("accent", c.accent),
            ("today", c.today),
            ("scheduled", c.scheduled),
            ("ready", c.ready),
            ("later", c.later),
            ("deadline", c.deadline),
        ]
        for (name, fg) in text {
            for (where_, back) in backgrounds {
                let ratio = contrast(RGB(fg), back)
                #expect(ratio >= 4.5, "\(scheme) \(name) on \(where_): \(ratio)")
            }
        }
    }

    @Test("paper text on accent buttons reaches 4.5:1", arguments: [ColorScheme.light, .dark])
    func buttonContrast(scheme: ColorScheme) {
        let c = DayruleColors.resolve(colorScheme: scheme)
        let ratio = contrast(RGB(c.bg), RGB(c.accent))
        #expect(ratio >= 4.5, "\(scheme) bg on accent: \(ratio)")
    }

    @Test("field boundaries reach 3:1 on bg and sidebar", arguments: [ColorScheme.light, .dark])
    func fieldBorderContrast(scheme: ColorScheme) {
        let c = DayruleColors.resolve(colorScheme: scheme)
        for (where_, back) in [("bg", RGB(c.bg)), ("sidebar", RGB(c.sidebar))] {
            for (name, border) in [("fieldBorder", c.fieldBorder), ("accent", c.accent)] {
                let ratio = contrast(RGB(border), back)
                #expect(ratio >= 3, "\(scheme) \(name) on \(where_): \(ratio)")
            }
        }
    }

    // MARK: Fraunces

    @Test("Fraunces-SemiBold resolves to the 600 weight instance")
    func frauncesSemiBold() throws {
        #if canImport(UIKit)
        let font = try #require(UIFont(name: "Fraunces-SemiBold", size: 17)) as CTFont
        #elseif canImport(AppKit)
        let font = try #require(NSFont(name: "Fraunces-SemiBold", size: 17)) as CTFont
        #endif
        #expect(CTFontCopyPostScriptName(font) as String == "Fraunces-SemiBold")
        let variation = try #require(CTFontCopyVariation(font) as? [NSNumber: NSNumber])
        let wght = NSNumber(value: 0x7767_6874) // 'wght'
        #expect(variation[wght]?.doubleValue == 600)
        #expect(DayruleFont.serifAvailable)
    }

    // MARK: Token hygiene

    @Test("raw Tokens.Light / Tokens.Dark stay inside Dayrule/Design/")
    func noRawSchemeTokensOutsideDesign() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DayruleTests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Dayrule", isDirectory: true)
        let design = app.appendingPathComponent("Design", isDirectory: true).standardizedFileURL.path + "/"
        let walker = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let path = url.standardizedFileURL.path
            if path.hasPrefix(design) { continue }
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("Tokens.Light.") || source.contains("Tokens.Dark.") {
                offenders.append(String(path.dropFirst(app.standardizedFileURL.path.count + 1)))
            }
        }
        #expect(scanned > 0, "no Swift sources found under \(app.path)")
        #expect(offenders.isEmpty, "use DayruleColors instead: \(offenders.sorted())")
    }

    // MARK: Dates (never raw ISO on screen)

    private static let locale = Locale(identifier: "en_GB")

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        cal.locale = locale
        return cal
    }

    private func relative(_ d: LocalDate, today: LocalDate) -> String {
        DayruleDateFormat.relative(d, today: today, locale: Self.locale, calendar: Self.calendar)
    }

    @Test("relative dates read as words near today")
    func relativeNear() {
        // 2026-10-13 is a Tuesday.
        #expect(relative("2026-10-13", today: "2026-10-13") == "Today")
        #expect(relative("2026-10-14", today: "2026-10-13") == "Tomorrow")
        #expect(relative("2026-10-12", today: "2026-10-13") == "Yesterday")
        #expect(relative("2026-10-16", today: "2026-10-13") == "Friday")
        #expect(relative("2026-10-19", today: "2026-10-13") == "Monday")
    }

    @Test("relative dates further out use day and month, with the year when it differs")
    func relativeFar() {
        #expect(relative("2026-10-14", today: "2026-10-01") == "14 Oct")
        #expect(relative("2026-10-01", today: "2026-10-13") == "1 Oct")
        #expect(relative("2027-01-05", today: "2026-12-20") == "5 Jan 2027")
        #expect(
            DayruleDateFormat.due("2026-10-14", today: "2026-10-13", locale: Self.locale, calendar: Self.calendar)
                == "Due Tomorrow"
        )
    }

    @Test("month headers read as month and year")
    func monthHeader() {
        #expect(DayruleDateFormat.month("2026-11", locale: Self.locale, calendar: Self.calendar) == "November 2026")
        #expect(DayruleDateFormat.month("2027-01", locale: Self.locale, calendar: Self.calendar) == "January 2027")
    }

    @Test("Scheduled day headers")
    func dayHeader() {
        let tomorrow = DayruleDateFormat.dayHeader(
            "2026-10-14", today: "2026-10-13", locale: Self.locale, calendar: Self.calendar
        )
        #expect(tomorrow.primary == "14")
        #expect(tomorrow.secondary == "Tomorrow")
        let later = DayruleDateFormat.dayHeader(
            "2026-10-16", today: "2026-10-13", locale: Self.locale, calendar: Self.calendar
        )
        #expect(later.primary == "16")
        #expect(later.secondary == "Friday")
    }

    // MARK: Completion linger

    /// Short injected linger so the suite stays fast; sleeps are fractions of it.
    private static let linger: Duration = .milliseconds(200)

    @Test("hold keeps a row visible until the linger ends, then folds it away")
    @MainActor
    func lingerHoldFolds() async throws {
        let store = LingerStore(linger: Self.linger, reduceMotion: { false })
        #expect(store.keepVisible == nil)
        store.hold("a")
        #expect(store.keepVisible == ["a"])
        try await Task.sleep(for: Self.linger / 2)
        #expect(store.ids == ["a"])
        try await Task.sleep(for: Self.linger)
        #expect(store.ids.isEmpty)
        #expect(store.keepVisible == nil)
    }

    @Test("holding again restarts the linger")
    @MainActor
    func lingerHoldRestarts() async throws {
        let store = LingerStore(linger: Self.linger, reduceMotion: { false })
        store.hold("a")
        try await Task.sleep(for: Self.linger * 0.6)
        store.hold("a")
        try await Task.sleep(for: Self.linger * 0.6)
        #expect(store.ids == ["a"])
        try await Task.sleep(for: Self.linger)
        #expect(store.ids.isEmpty)
    }

    @Test("release drops a row at once and cancels its fold")
    @MainActor
    func lingerRelease() async throws {
        let store = LingerStore(linger: Self.linger, reduceMotion: { false })
        store.hold("a")
        store.hold("b")
        store.release("a")
        #expect(store.ids == ["b"])
        // A re-hold after release starts a fresh linger, unaffected by the cancelled one.
        store.hold("a")
        #expect(store.ids == ["a", "b"])
    }

    @Test("clear forgets every held row")
    @MainActor
    func lingerClear() async throws {
        let store = LingerStore(linger: Self.linger, reduceMotion: { false })
        store.hold("a")
        store.hold("b")
        store.clear()
        #expect(store.ids.isEmpty)
        #expect(store.keepVisible == nil)
        // Cancelled folds must not touch rows held after the clear.
        store.hold("c")
        try await Task.sleep(for: Self.linger / 2)
        #expect(store.ids == ["c"])
    }

    @Test("Reduce Motion fades the row out before the list closes the gap")
    @MainActor
    func lingerReduceMotionFades() async throws {
        let store = LingerStore(linger: Self.linger, reduceMotion: { true })
        store.hold("a")
        #expect(store.fading.isEmpty)
        // Past the linger, inside the fade: still listed, drawn transparent.
        try await Task.sleep(for: Self.linger + Motion.fadeDuration / 3)
        #expect(store.ids == ["a"])
        #expect(store.fading == ["a"])
        try await Task.sleep(for: Motion.fadeDuration * 2)
        #expect(store.ids.isEmpty)
        #expect(store.fading.isEmpty)
    }

    @Test("release during the Reduce Motion fade drops the row and its fade")
    @MainActor
    func lingerReduceMotionRelease() async throws {
        let store = LingerStore(linger: Self.linger, reduceMotion: { true })
        store.hold("a")
        try await Task.sleep(for: Self.linger + Motion.fadeDuration / 3)
        #expect(store.fading == ["a"])
        store.release("a")
        #expect(store.ids.isEmpty)
        #expect(store.fading.isEmpty)
        // A re-hold starts fresh and isn't drawn faded.
        store.hold("a")
        try await Task.sleep(for: Self.linger / 2)
        #expect(store.ids == ["a"])
        #expect(store.fading.isEmpty)
    }
}

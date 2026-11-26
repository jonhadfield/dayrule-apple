import SwiftUI

/// Paper-and-ink tokens mirrored from `dayrule/web/src/styles/tokens.css`.
enum Tokens {
    enum Light {
        static let bg = Color(hex: 0xF7F3EC)
        static let sidebar = Color(hex: 0xEFE8DC)
        static let text = Color(hex: 0x1F1B16)
        static let textSecondary = Color(hex: 0x6D6459)
        static let hairline = Color(hex: 0xE2D9CB)
        static let accent = Color(hex: 0xAA4628)
        static let today = Color(hex: 0xAA4628)
        static let scheduled = Color(hex: 0x8E5A18)
        static let ready = Color(hex: 0x4F6B3A)
        static let later = Color(hex: 0x5D6771)
        static let done = Color(hex: 0x4F6B3A)
        static let deadline = Color(hex: 0xB3261E)
    }

    enum Dark {
        static let bg = Color(hex: 0x1B1814)
        static let sidebar = Color(hex: 0x221E19)
        static let text = Color(hex: 0xEDE6DA)
        static let textSecondary = Color(hex: 0xA0968A)
        static let hairline = Color(hex: 0x3A332B)
        static let accent = Color(hex: 0xE07A55)
        static let today = Color(hex: 0xE07A55)
        static let scheduled = Color(hex: 0xD9A14E)
        static let ready = Color(hex: 0x8FAE74)
        static let later = Color(hex: 0x9AA6B2)
        static let done = Color(hex: 0x8FAE74)
        static let deadline = Color(hex: 0xE5735F)
    }

    static let radiusRow: CGFloat = 4
    static let radiusCard: CGFloat = 6
    static let radiusPopover: CGFloat = 8
    /// Phone to-do rows; a touch under the old 46 so text sits closer to hairlines.
    static let rowHeightPhone: CGFloat = 42

    // MARK: Native-only layout (not mirrored from tokens.css; see PLAN §6.1)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    static let rowInset: CGFloat = 16
    /// Shared height for Mac sidebar footer (New List) and pinned Add shelf.
    /// 48pt leaves a little air above/below the controls in the tinted shelf.
    static let macBottomChromeHeight: CGFloat = 48
    /// Settings / sheet chapter titles (decision 58 Mac rail; PLAN decision 68).
    static let sheetInset: CGFloat = 20
    /// AppKit plain `List` leading bias vs chrome drawn outside the table (Mac).
    /// iOS lists have no extra system inset, so chrome and rows share `rowInset`.
    #if os(macOS)
    /// Tuned so pinned Add’s disc shares the checkbox column centre (system
    /// table inset + `rowInset`), measured against Mac plain Lists.
    static let macListSystemLeading: CGFloat = 30
    #else
    static let macListSystemLeading: CGFloat = 0
    #endif
    /// Horizontal inset for pinned Add / selection chrome so the leading mark
    /// column (centre) lines up with checkboxes inside the list.
    static var listChromeInset: CGFloat { rowInset + macListSystemLeading }
    /// Offset from the leading-slot rail to the checkbox circle’s left edge
    /// (20pt mark centred in `rowLeadingSlot`).
    static var listMarkCircleLeading: CGFloat { (rowLeadingSlot - 20) / 2 }
    /// Leading spacer width for Scheduled day numbers inside Mac plain Lists.
    /// Those flat headers ignore `listRowInsets` / padding / `Color.clear`; a
    /// figure-space `frame` of this width lands digit ink on the circle edge
    /// (system table origin ≈ 30pt + row inset + mark pad).
    #if os(macOS)
    /// Empirically: system origin (~30) + this ≈ circle left (~50). Was 20 with
    /// day still ~17pt right of circles; 4 lands the digit on the mark edge.
    static let macScheduledDayLeading: CGFloat = 4
    #else
    static var macScheduledDayLeading: CGFloat { rowInset + listMarkCircleLeading }
    #endif
    static let rowGlyphSpacing: CGFloat = 10
    static let rowLeadingSlot: CGFloat = 28
    /// Web `--row-height` at 900px and up.
    static let rowHeightDesktop: CGFloat = 36
    /// Prefer `rowMinHeight(dense:)` / `RuledRow` (reads `dayruleDenseLayout`).
    /// Static default is phone on iOS so compact call sites stay correct.
    #if os(macOS)
    static let rowHeight: CGFloat = rowHeightDesktop
    #else
    static let rowHeight: CGFloat = rowHeightPhone
    #endif

    /// Dense (Mac / iPad regular): 36. Phone compact: `rowHeightPhone`.
    static func rowMinHeight(dense: Bool) -> CGFloat {
        dense ? rowHeightDesktop : rowHeightPhone
    }
    static let formMaxWidth: CGFloat = 420
    static let readingMaxWidth: CGFloat = 720
    static let minHit: CGFloat = 44
    static let badgeSize: CGFloat = 28

    /// Side margin that centres content in `readingMaxWidth` on wide windows.
    static func readingMargin(width: CGFloat, compact: Bool) -> CGFloat {
        guard !compact else { return 0 }
        return max(0, (width - readingMaxWidth) / 2)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct DayruleColors {
    let bg: Color
    let sidebar: Color
    let text: Color
    let textSecondary: Color
    let hairline: Color
    let accent: Color
    let deadline: Color
    let today: Color
    let scheduled: Color
    let ready: Color
    let later: Color
    let done: Color
    /// Increase Contrast — stronger secondary ink and hairlines.
    let increasedContrast: Bool
    /// Reduce Transparency — prefer more opaque washes over paper.
    let reduceTransparency: Bool

    /// Selection wash stays at 10% so chip / accent ink still clear 4.5:1
    /// (`DesignSystemTests`); Increase Contrast strengthens hairlines / secondary
    /// ink / borders instead of deepening this wash.
    var selectedRowAlpha: Double { 0.10 }
    var selectedRow: Color { accent.opacity(selectedRowAlpha) }
    var pressed: Color {
        // Slightly denser under Reduce Transparency / Increase Contrast without
        // swapping to opaque sidebar (that broke secondary ink ratios).
        let alpha: Double = {
            if reduceTransparency { return increasedContrast ? 0.78 : 0.72 }
            return increasedContrast ? 0.68 : 0.6
        }()
        return sidebar.opacity(alpha)
    }
    var deadlineTint: Color {
        deadline.opacity(increasedContrast || reduceTransparency ? 0.14 : 0.10)
    }
    var ruleStrong: Color { text }
    var checkboxBorder: Color { text.opacity(increasedContrast ? 0.72 : 0.5) }
    /// Unfocused text-field boundary: non-text contrast ≥3:1 on bg and sidebar.
    var fieldBorder: Color { textSecondary }
    /// Soft sidebar wash for cards / tips; solid sidebar when Reduce Transparency.
    var sidebarWash: Color {
        reduceTransparency ? sidebar : sidebar.opacity(increasedContrast ? 0.75 : 0.4)
    }

    private func washAlpha(standard: Double, increased: Double, solidFloor: Double) -> Double {
        var alpha = increasedContrast ? increased : standard
        if reduceTransparency { alpha = max(alpha, solidFloor) }
        return alpha
    }

    static func resolve(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast = .standard,
        reduceTransparency: Bool = false
    ) -> DayruleColors {
        let increased = contrast == .increased
        switch colorScheme {
        case .dark:
            return DayruleColors(
                bg: Tokens.Dark.bg,
                sidebar: Tokens.Dark.sidebar,
                text: Tokens.Dark.text,
                textSecondary: increased
                    ? Color(hex: 0xC4BBAF)
                    : Tokens.Dark.textSecondary,
                hairline: increased
                    ? Color(hex: 0x5A5248)
                    : Tokens.Dark.hairline,
                accent: Tokens.Dark.accent,
                deadline: Tokens.Dark.deadline,
                today: Tokens.Dark.today,
                scheduled: Tokens.Dark.scheduled,
                ready: Tokens.Dark.ready,
                later: Tokens.Dark.later,
                done: Tokens.Dark.done,
                increasedContrast: increased,
                reduceTransparency: reduceTransparency
            )
        default:
            return DayruleColors(
                bg: Tokens.Light.bg,
                sidebar: Tokens.Light.sidebar,
                text: Tokens.Light.text,
                textSecondary: increased
                    ? Color(hex: 0x4A433C)
                    : Tokens.Light.textSecondary,
                hairline: increased
                    ? Color(hex: 0xC4B8A8)
                    : Tokens.Light.hairline,
                accent: Tokens.Light.accent,
                deadline: Tokens.Light.deadline,
                today: Tokens.Light.today,
                scheduled: Tokens.Light.scheduled,
                ready: Tokens.Light.ready,
                later: Tokens.Light.later,
                done: Tokens.Light.done,
                increasedContrast: increased,
                reduceTransparency: reduceTransparency
            )
        }
    }
}

/// Resolves paper colours from the current scheme + accessibility display prefs.
@propertyWrapper
struct DayrulePalette: DynamicProperty {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var wrappedValue: DayruleColors {
        DayruleColors.resolve(
            colorScheme: colorScheme,
            contrast: contrast,
            reduceTransparency: reduceTransparency
        )
    }
}

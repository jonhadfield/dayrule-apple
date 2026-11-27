import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum DayruleFont {
    static let serifFamily = "Fraunces"

    /// Named instances of the bundled variable font. The family name alone resolves
    /// to the default (Regular) instance and ignores weight, so always go by PostScript name.
    private static func postScriptName(for w: Font.Weight) -> String {
        switch w {
        case .regular: "Fraunces-Regular"
        case .bold, .heavy, .black: "Fraunces-Bold"
        default: "Fraunces-SemiBold"
        }
    }

    static let serifAvailable: Bool = {
        #if canImport(UIKit)
        UIFont(name: "Fraunces-SemiBold", size: 12) != nil
        #elseif canImport(AppKit)
        NSFont(name: "Fraunces-SemiBold", size: 12) != nil
        #else
        false
        #endif
    }()

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        guard serifAvailable else { return .system(style, design: .serif).weight(weight) }
        return .custom(postScriptName(for: weight), size: size(for: style), relativeTo: style)
    }

    static func brand() -> Font {
        guard serifAvailable else { return .system(.largeTitle, design: .serif).weight(.semibold) }
        return .custom("Fraunces-SemiBold", size: 34, relativeTo: .largeTitle)
    }

    static func listTitle() -> Font {
        guard serifAvailable else { return .system(.title, design: .serif).weight(.semibold) }
        return .custom("Fraunces-SemiBold", size: 30, relativeTo: .title)
    }

    #if os(iOS)
    /// Dynamic Type scaled Fraunces SemiBold for UIKit chrome (nav bar titles).
    static func uiFont(_ textStyle: UIFont.TextStyle, size: CGFloat) -> UIFont {
        let base = UIFont(name: "Fraunces-SemiBold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
    #endif

    private static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 30
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

/// Dense layout (PLAN §6.2 / §6.5): Mac always; iOS when `horizontalSizeClass`
/// is regular (iPad / Duo open). Phone compact stays Dynamic Type body.
private struct DayruleDenseLayoutKey: EnvironmentKey {
    #if os(macOS)
    static let defaultValue = true
    #else
    static let defaultValue = false
    #endif
}

private struct DayruleReadingMarginKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// 15pt row type + 36pt row min-height (web desktop / Mac).
    var dayruleDenseLayout: Bool {
        get { self[DayruleDenseLayoutKey.self] }
        set { self[DayruleDenseLayoutKey.self] = newValue }
    }

    /// Extra horizontal inset that centres the reading column on wide windows
    /// (PLAN decision 68). Page titles and selection chrome read this too.
    var dayruleReadingMargin: CGFloat {
        get { self[DayruleReadingMarginKey.self] }
        set { self[DayruleReadingMarginKey.self] = newValue }
    }
}

/// Type roles (PLAN §6.2). List row/link titles use 16pt except at
/// accessibility Dynamic Type sizes, which use scalable body. Fixed-size roles
/// also honour system Bold Text via `legibilityWeight` in the view modifiers.
///
/// Glyphs inside meta text (bell, repeat, notes) use the same font as the text
/// plus `.imageScale(.small)`, never a fixed point size.
enum DayruleType {
    static var brand: Font { DayruleFont.brand() }
    static var pageTitle: Font { DayruleFont.listTitle() }
    static var sheetTitle: Font { DayruleFont.serif(.title3) }
    static var sectionSerif: Font { DayruleFont.serif(.headline) }

    static let sectionHeader: Font = .footnote.weight(.semibold)
    /// Prefer `View.dayruleRowTitle()`. Static default is the list item size.
    static let rowTitle: Font = .system(size: 16)
    static let link: Font = .system(size: 16)
    /// Chip / subtitle / overdue (“1d overdue”) — 14pt (was footnote ≈13).
    /// Prefer `View.dayruleMeta()` so Bold Text is applied.
    static let meta: Font = .system(size: 14)
    static let helper: Font = .footnote
    static let error: Font = .footnote
    static let button: Font = .headline
    static let count: Font = .subheadline.monospacedDigit()
    static let tabLabel: Font = .caption2.weight(.medium)

    /// Tightened tracking for brand and page titles.
    static let titleTracking: CGFloat = -0.5

    /// List item titles: 16pt for default sizes (phone + dense); body when the
    /// system accessibility text size is on. `dense` is kept for call-site
    /// clarity; both layouts share the same list size now.
    static func rowTitle(dense: Bool, accessibilitySize: Bool = false) -> Font {
        _ = dense
        if accessibilitySize { return Font.body }
        return Font.system(size: 16)
    }

    static func link(dense: Bool, accessibilitySize: Bool = false) -> Font {
        rowTitle(dense: dense, accessibilitySize: accessibilitySize)
    }

    /// Meta / chip size; `bold` mirrors system Bold Text.
    static func meta(bold: Bool = false) -> Font {
        Font.system(size: 14).weight(bold ? .bold : .regular)
    }

    /// Resolved weight when the caller passes an optional role weight and Bold Text is on.
    static func resolvedWeight(_ preferred: Font.Weight?, boldText: Bool) -> Font.Weight? {
        if boldText { return .bold }
        return preferred
    }
}

private struct DayruleRowTitleModifier: ViewModifier {
    @Environment(\.dayruleDenseLayout) private var dense
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    var weight: Font.Weight?

    func body(content: Content) -> some View {
        let base = DayruleType.rowTitle(
            dense: dense,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        let resolved = DayruleType.resolvedWeight(
            weight,
            boldText: legibilityWeight == .bold
        )
        content.font(resolved.map { base.weight($0) } ?? base)
    }
}

private struct DayruleLinkModifier: ViewModifier {
    @Environment(\.dayruleDenseLayout) private var dense
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        let base = DayruleType.link(
            dense: dense,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        content.font(
            legibilityWeight == .bold ? base.weight(.bold) : base
        )
    }
}

private struct DayruleMetaModifier: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight
    var weight: Font.Weight?

    func body(content: Content) -> some View {
        if legibilityWeight == .bold {
            content.font(DayruleType.meta(bold: true))
        } else if let weight {
            content.font(Font.system(size: 14).weight(weight))
        } else {
            content.font(DayruleType.meta(bold: false))
        }
    }
}

extension View {
    /// Row title that follows `dayruleDenseLayout` (16pt default / body at AX)
    /// and system Bold Text.
    func dayruleRowTitle(_ weight: Font.Weight? = nil) -> some View {
        modifier(DayruleRowTitleModifier(weight: weight))
    }

    func dayruleLink() -> some View {
        modifier(DayruleLinkModifier())
    }

    /// Meta / chip / overdue type (14pt) that follows system Bold Text.
    func dayruleMeta(_ weight: Font.Weight? = nil) -> some View {
        modifier(DayruleMetaModifier(weight: weight))
    }
}

/// Default `Text` / control font for dense chrome (Mac DayruleApp parity).
/// Accessibility Dynamic Type sizes keep the system body scale instead of 15pt.
/// Honours system Bold Text when pinning the dense size.
struct DayruleDenseBodyFont: ViewModifier {
    var dense: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        if dense, !dynamicTypeSize.isAccessibilitySize {
            let font = Font.system(size: 15)
                .weight(legibilityWeight == .bold ? .bold : .regular)
            content.environment(\.font, font)
        } else {
            content
        }
    }
}

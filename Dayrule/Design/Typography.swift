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

/// Type roles (PLAN §6.2). Every role is Dynamic Type relative.
///
/// Glyphs inside meta text (bell, repeat, notes) use the same font as the text
/// plus `.imageScale(.small)`, never a fixed point size.
enum DayruleType {
    static var brand: Font { DayruleFont.brand() }
    static var pageTitle: Font { DayruleFont.listTitle() }
    static var sheetTitle: Font { DayruleFont.serif(.title3) }
    static var sectionSerif: Font { DayruleFont.serif(.headline) }

    static let sectionHeader: Font = .footnote.weight(.semibold)
    /// `.body` on both platforms (13pt system on macOS).
    static let rowTitle: Font = .body
    static let meta: Font = .footnote
    static let helper: Font = .footnote
    static let error: Font = .footnote
    static let button: Font = .headline
    static let link: Font = .body
    static let count: Font = .subheadline.monospacedDigit()
    static let tabLabel: Font = .caption2.weight(.medium)

    /// Tightened tracking for brand and page titles.
    static let titleTracking: CGFloat = -0.5
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum DayruleFont {
    static let serifFamily = "Fraunces"

    /// Prefer the postscript name of the variable font; fall back if not bundled yet.
    private static var serifAvailable: Bool {
        #if canImport(UIKit)
        UIFont.fontNames(forFamilyName: serifFamily).isEmpty == false
            || UIFont(name: "FrauncesRoman-SemiBold", size: 12) != nil
            || UIFont(name: serifFamily, size: 12) != nil
        #elseif canImport(AppKit)
        NSFontManager.shared.availableMembers(ofFontFamily: serifFamily) != nil
        #else
        false
        #endif
    }

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        guard serifAvailable else { return .system(style, design: .serif).weight(weight) }
        // Variable Fraunces: avoid `.weight` (can fault when the face isn't registered).
        return .custom(serifFamily, size: size(for: style), relativeTo: style)
    }

    static func brand() -> Font {
        guard serifAvailable else { return .system(.largeTitle, design: .serif).weight(.semibold) }
        return .custom(serifFamily, size: 34, relativeTo: .largeTitle)
    }

    static func listTitle() -> Font {
        guard serifAvailable else { return .system(.title, design: .serif).weight(.semibold) }
        return .custom(serifFamily, size: 30, relativeTo: .title)
    }

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

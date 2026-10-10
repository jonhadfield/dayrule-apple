import SwiftUI

enum DayruleFont {
    static let serifFamily = "Fraunces"

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .custom(serifFamily, size: size(for: style), relativeTo: style)
            .weight(weight)
    }

    static func brand() -> Font {
        .custom(serifFamily, size: 34, relativeTo: .largeTitle).weight(.semibold)
    }

    static func listTitle() -> Font {
        .custom(serifFamily, size: 30, relativeTo: .title).weight(.semibold)
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

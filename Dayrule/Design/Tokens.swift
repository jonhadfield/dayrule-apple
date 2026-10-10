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
    static let rowHeightPhone: CGFloat = 46
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

    static func resolve(colorScheme: ColorScheme) -> DayruleColors {
        switch colorScheme {
        case .dark:
            DayruleColors(
                bg: Tokens.Dark.bg,
                sidebar: Tokens.Dark.sidebar,
                text: Tokens.Dark.text,
                textSecondary: Tokens.Dark.textSecondary,
                hairline: Tokens.Dark.hairline,
                accent: Tokens.Dark.accent
            )
        case .light:
            fallthrough
        @unknown default:
            DayruleColors(
                bg: Tokens.Light.bg,
                sidebar: Tokens.Light.sidebar,
                text: Tokens.Light.text,
                textSecondary: Tokens.Light.textSecondary,
                hairline: Tokens.Light.hairline,
                accent: Tokens.Light.accent
            )
        }
    }
}

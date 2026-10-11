import SwiftUI

/// Per-device appearance (UserDefaults; PLAN §6.1 / §12). Not synced.
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum DeviceAppearancePrefs {
    private static let key = "dayrule.appearance"

    static var preference: AppearancePreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = AppearancePreference(rawValue: raw)
            else { return .system }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

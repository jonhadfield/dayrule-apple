import Foundation

/// Platform identity for `X-Dayrule-Client` and login `deviceLabel` (PLAN §9).
enum ClientPlatform {
    static var kind: String {
        #if os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }

    static var deviceLabel: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    static func clientHeader(build: String) -> String {
        "\(kind)/\(build)"
    }
}

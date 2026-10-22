import Foundation

/// Default API base URL (PLAN §9.6).
/// Gate / Release default is production. The Advanced Server field is an
/// override: blank means this default; a typed URL is kept if Advanced
/// collapses. `DAYRULE_API` is a Debug scheme / UI-test / CI override;
/// Release always uses production.
enum APIConfig {
    static let production = "https://dayrule.app"
    static let localDev = "http://127.0.0.1:8080"

    /// True when Debug was launched with `DAYRULE_API` (UI tests / CI).
    static var hasLaunchOverride: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["DAYRULE_API"]?.isEmpty == false
        #else
        false
        #endif
    }

    /// `DAYRULE_API` overrides when set in Debug. Release always returns production.
    static var defaultBaseURLString: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["DAYRULE_API"],
           !override.isEmpty
        {
            return override
        }
        #endif
        return production
    }

    /// Gate API field is an override. Blank / whitespace uses the launch default.
    static func resolvedBaseURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBaseURLString : trimmed
    }

    static func resolvedBaseURL(_ raw: String) -> URL? {
        URL(string: resolvedBaseURLString(raw))
    }
}

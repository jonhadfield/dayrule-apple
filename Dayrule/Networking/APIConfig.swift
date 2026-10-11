import Foundation

/// Default API base URL (PLAN §9.6).
/// Debug → local Go server; Release / TestFlight → production.
enum APIConfig {
    static let production = "https://dayrule.app"
    static let localDev = "http://127.0.0.1:8080"

    /// `DAYRULE_API` overrides when set (Xcode scheme / UI tests / CI).
    static var defaultBaseURLString: String {
        if let override = ProcessInfo.processInfo.environment["DAYRULE_API"],
           !override.isEmpty
        {
            return override
        }
        #if DEBUG
        return localDev
        #else
        return production
        #endif
    }
}

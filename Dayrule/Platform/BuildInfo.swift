import Foundation

enum BuildInfo {
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// Short git SHA stamped into Info.plist by the Embed git commit build phase.
    static var gitCommit: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "DayruleGitCommit") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    static var aboutVersionLine: String {
        "Dayrule \(shortVersion) (\(build))"
    }
}

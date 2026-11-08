import Foundation

/// Constants for the Share → Inbox encrypted queue (PLAN §1 / decision 39).
/// The queue key never unwraps the account key.
enum ShareInboxSupport {
    static let appGroupId = "group.uk.co.lessknown.dayrule"
    /// Keychain access group shared by the app and the share extension.
    /// Prefix is the Apple Team ID (`DEVELOPMENT_TEAM` in project.yml).
    static let keychainAccessGroup = "VBZY8FBYR5.uk.co.lessknown.dayrule.shareinbox"
    static let keychainService = "uk.co.lessknown.dayrule.share-inbox-key"
    static let queueFileName = "inbox-queue.json"
    static let formatVersion = 1

    /// Test override for the queue file (unit tests without an App Group container).
    nonisolated(unsafe) static var queueURLOverride: URL?
    /// Test override for the 32-byte queue key (avoids Keychain / access-group entitlements in CI).
    nonisolated(unsafe) static var keyOverride: [UInt8]?

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    static var queueURL: URL? {
        if let queueURLOverride { return queueURLOverride }
        return containerURL?.appendingPathComponent(queueFileName, isDirectory: false)
    }
}

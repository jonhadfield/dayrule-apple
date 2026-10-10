import Foundation

/// User-visible sync state (PLAN §10 / M4 Settings).
enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case synced
    case offline(String)
    case blocked(String)
    /// Server sent a record with an unknown `alg` — keep ciphertext, stop merging it.
    case needsUpdate

    var label: String {
        switch self {
        case .idle: "Not synced yet"
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .offline(let m): m
        case .blocked(let m): m
        case .needsUpdate: "Update Dayrule to sync newer records."
        }
    }
}

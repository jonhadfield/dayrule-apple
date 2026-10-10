import Foundation

/// Network surface used by `SyncEngine` (web `SyncTransport`).
protocol SyncTransport: Sendable {
    func pull(since: Int64, full: Bool) async throws -> PullResponse
    func push(_ records: [PushWireRecord]) async throws -> PushResponse
}

extension APIClient: SyncTransport {}

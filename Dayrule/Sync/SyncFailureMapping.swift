import Foundation

/// Maps sync transport errors to UI status (PLAN §10.4 / §9.2).
enum SyncFailureMapping {
    struct Effect: Equatable {
        var status: SyncStatus?
        var errorMessage: String?
        /// Clear Bearer and return to gate (401 / unauthorized).
        var signOut: Bool
    }

    static func effect(for error: Error) -> Effect {
        if let blocked = error as? SyncBlockedError {
            let message = blocked.localizedDescription
            return Effect(status: .blocked(message), errorMessage: message, signOut: false)
        }
        if let api = error as? APIError {
            switch api {
            case let .http(status, code, _) where status == 401 || code == "unauthorized":
                return Effect(status: nil, errorMessage: "Sign in again", signOut: true)
            case let .http(status, code, message) where status == 426 || code == "upgrade_required":
                let text = message.isEmpty ? SyncStatus.needsUpdate.label : message
                return Effect(status: .needsUpdate, errorMessage: text, signOut: false)
            case .offline:
                let text = "Offline — changes stay on this device."
                return Effect(status: .offline(text), errorMessage: text, signOut: false)
            case let .http(_, _, message):
                let text = message.isEmpty ? api.localizedDescription : message
                return Effect(status: .offline(text), errorMessage: text, signOut: false)
            case .decoding:
                let text = api.localizedDescription
                return Effect(status: .offline(text), errorMessage: text, signOut: false)
            }
        }
        let text = error.localizedDescription
        return Effect(status: .offline(text), errorMessage: text, signOut: false)
    }
}

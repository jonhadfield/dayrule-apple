import AuthenticationServices
import Foundation

/// System Passwords / iCloud Keychain via `ASAuthorizationPasswordProvider`.
/// Prefer this on Mac: SwiftUI `SecureField` AutoFill often fills username only
/// (or never inserts into the password field).
enum PasswordAuthorization {
    struct Credential: Sendable {
        var user: String
        var password: String
    }

    enum Error: Swift.Error, Equatable {
        case cancelled
        case failed(String)
        case unexpectedCredential
    }

    @MainActor
    static func requestSavedPassword() async throws -> Credential {
        let request = ASAuthorizationPasswordProvider().createRequest()
        let credential = try await PasskeyAuthorization.perform(request)
        guard let passwordCredential = credential as? ASPasswordCredential else {
            throw Error.unexpectedCredential
        }
        return Credential(user: passwordCredential.user, password: passwordCredential.password)
    }
}

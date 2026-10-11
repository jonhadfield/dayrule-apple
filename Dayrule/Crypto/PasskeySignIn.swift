import AuthenticationServices
import Foundation

/// Server-verified WebAuthn assertion for two-step sign-in (PLAN §9.3 / decision 30).
/// Distinct from device-local PRF unlock (`PasskeyPRF`).
enum PasskeySignIn {
    enum Error: Swift.Error, LocalizedError, Equatable {
        case badOptions
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .badOptions:
                "The passkey challenge from the server wasn’t usable."
            case .cancelled:
                "Passkey sign-in was cancelled."
            case .failed(let s):
                s
            }
        }
    }

    /// Run the platform assertion for `options` (the `options` object from
    /// `POST /api/v1/auth/login/passkey/options`) and return the credential
    /// JSON `go-webauthn` expects.
    @MainActor
    static func assert(options: [String: Any]) async throws -> [String: Any] {
        guard let pk = options["publicKey"] as? [String: Any],
              let challengeB64 = pk["challenge"] as? String,
              let challenge = try? Base64URL.decode(challengeB64)
        else { throw Error.badOptions }

        let rpId = (pk["rpId"] as? String) ?? PasskeyPRF.relyingPartyId
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialAssertionRequest(challenge: Data(challenge))
        if let allow = pk["allowCredentials"] as? [[String: Any]] {
            request.allowedCredentials = allow.compactMap { item in
                guard let id = item["id"] as? String,
                      let bytes = try? Base64URL.decode(id)
                else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: Data(bytes))
            }
        }
        if let uv = pk["userVerification"] as? String {
            switch uv {
            case "required": request.userVerificationPreference = .required
            case "discouraged": request.userVerificationPreference = .discouraged
            default: request.userVerificationPreference = .preferred
            }
        } else {
            request.userVerificationPreference = .preferred
        }

        do {
            let credential = try await PasskeyAuthorization.perform(request)
            guard let assertion = credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion
            else { throw Error.failed("No passkey assertion was returned.") }
            return credentialJSON(assertion)
        } catch let err as PasskeyPRF.Error {
            switch err {
            case .cancelled: throw Error.cancelled
            case .unsupported, .failed: throw Error.failed(err.localizedDescription ?? "Passkey failed.")
            }
        } catch let err as Error {
            throw err
        } catch {
            throw Error.failed(error.localizedDescription)
        }
    }

    private static func credentialJSON(
        _ assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion
    ) -> [String: Any] {
        var response: [String: Any] = [
            "clientDataJSON": Base64URL.encode(assertion.rawClientDataJSON),
            "authenticatorData": Base64URL.encode(assertion.rawAuthenticatorData),
            "signature": Base64URL.encode(assertion.signature),
        ]
        if let handle = assertion.userID, !handle.isEmpty {
            response["userHandle"] = Base64URL.encode(handle)
        }
        return [
            "id": Base64URL.encode(assertion.credentialID),
            "rawId": Base64URL.encode(assertion.credentialID),
            "type": "public-key",
            "authenticatorAttachment": "platform",
            "clientExtensionResults": [String: Any](),
            "response": response,
        ]
    }
}

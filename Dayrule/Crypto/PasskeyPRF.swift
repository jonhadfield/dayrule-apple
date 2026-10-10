import AuthenticationServices
import CryptoKit
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Platform passkey PRF ceremony for device-local unlock (PLAN §8.4).
/// The assertion is never sent to the server — only the PRF bytes matter.
enum PasskeyPRF {
    static let relyingPartyId = "dayrule.app"

    enum Error: Swift.Error, LocalizedError, Equatable {
        case unsupported
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                "This device can’t unlock with a passkey (it needs passkeys with the PRF extension)."
            case .cancelled:
                "Passkey unlock was cancelled."
            case .failed(let s):
                s
            }
        }
    }

    struct Enrollment: Sendable {
        var credentialId: [UInt8]
        var salt: [UInt8]
        var prf: [UInt8]
    }

    /// Create a platform passkey and return credential id, salt, and PRF output.
    @MainActor
    static func enroll(userId: String, email: String) async throws -> Enrollment {
        let salt = Primitives.randomBytes(32)
        let challenge = Data(Primitives.randomBytes(32))
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyId
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: email,
            userID: Data(userId.utf8)
        )
        request.userVerificationPreference = .required
        let saltValues = ASAuthorizationPublicKeyCredentialPRFAssertionInput.InputValues
            .saltInput1(Data(salt))
        request.prf = ASAuthorizationPublicKeyCredentialPRFRegistrationInput.inputValues(saltValues)

        let credential = try await perform(request)
        guard let reg = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration
        else { throw Error.failed("No passkey was created.") }

        let credentialId = [UInt8](reg.credentialID)
        if let first = reg.prf?.first {
            return Enrollment(credentialId: credentialId, salt: salt, prf: symmetricKeyBytes(first))
        }
        if reg.prf?.isSupported == false {
            throw Error.unsupported
        }
        // Some authenticators only evaluate PRF on assertion.
        let prf = try await assert(credentialId: credentialId, salt: salt)
        return Enrollment(credentialId: credentialId, salt: salt, prf: prf)
    }

    /// Assert with allow-list + PRF salt; returns PRF output bytes.
    @MainActor
    static func assert(credentialId: [UInt8], salt: [UInt8]) async throws -> [UInt8] {
        let challenge = Data(Primitives.randomBytes(32))
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyId
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = [
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: Data(credentialId)),
        ]
        request.userVerificationPreference = .required
        let saltValues = ASAuthorizationPublicKeyCredentialPRFAssertionInput.InputValues
            .saltInput1(Data(salt))
        request.prf = ASAuthorizationPublicKeyCredentialPRFAssertionInput.inputValues(saltValues)

        do {
            let credential = try await perform(request)
            guard let assertion = credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion,
                  let first = assertion.prf?.first
            else { throw Error.unsupported }
            return symmetricKeyBytes(first)
        } catch let err as Error {
            throw err
        } catch {
            throw Error.failed(
                "The passkey wasn’t used, or isn’t on this device any more. You can unlock with your password."
            )
        }
    }

    @MainActor
    private static func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { cont in
            let proxy = ControllerProxy(continuation: cont)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = proxy
            controller.presentationContextProvider = proxy
            proxy.retain(controller)
            controller.performRequests()
        }
    }

    private static func symmetricKeyBytes(_ key: SymmetricKey) -> [UInt8] {
        key.withUnsafeBytes { Array($0) }
    }
}

@MainActor
private final class ControllerProxy: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<ASAuthorizationCredential, any Error>?
    private var controller: ASAuthorizationController?

    init(continuation: CheckedContinuation<ASAuthorizationCredential, any Error>) {
        self.continuation = continuation
    }

    func retain(_ controller: ASAuthorizationController) {
        self.controller = controller
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: \.isKeyWindow) { return key }
            if let any = windowScene.windows.first { return any }
        }
        return UIWindow(frame: .zero)
        #else
        if let key = NSApplication.shared.keyWindow { return key }
        if let any = NSApplication.shared.windows.first { return any }
        return NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        #endif
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization.credential)
        continuation = nil
        self.controller = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue
        {
            continuation?.resume(throwing: PasskeyPRF.Error.cancelled)
        } else {
            continuation?.resume(throwing: PasskeyPRF.Error.failed(error.localizedDescription))
        }
        continuation = nil
        self.controller = nil
    }
}

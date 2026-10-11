import AuthenticationServices
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shared `ASAuthorizationController` runner for PRF unlock and sign-in passkeys.
enum PasskeyAuthorization {
    @MainActor
    static func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { cont in
            let proxy = ControllerProxy(continuation: cont)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = proxy
            controller.presentationContextProvider = proxy
            proxy.retain(controller)
            controller.performRequests()
        }
    }
}

@MainActor
final class ControllerProxy: NSObject,
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

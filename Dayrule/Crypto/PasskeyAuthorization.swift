import AuthenticationServices
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shared `ASAuthorizationController` runner for PRF unlock and sign-in passkeys.
enum PasskeyAuthorization {
    /// `ASAuthorizationController.delegate` is weak — keep the proxy alive until
    /// the ceremony finishes, or the continuation never resumes (Mac Settings
    /// “Unlock with passkey” spinner never stops).
    @MainActor
    private static var inFlight: ControllerProxy?

    @MainActor
    static func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { cont in
            let proxy = ControllerProxy(continuation: cont) {
                inFlight = nil
            }
            inFlight = proxy
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
    private let onFinish: () -> Void

    init(
        continuation: CheckedContinuation<ASAuthorizationCredential, any Error>,
        onFinish: @escaping () -> Void
    ) {
        self.continuation = continuation
        self.onFinish = onFinish
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
        // Prefer the key window (often the Settings sheet) so the system sheet
        // anchors correctly; fall back to any visible titled window.
        if let key = NSApplication.shared.keyWindow, key.isVisible { return key }
        if let main = NSApplication.shared.mainWindow, main.isVisible { return main }
        if let titled = NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.styleMask.contains(.titled)
        }) {
            return titled
        }
        if let any = NSApplication.shared.windows.first { return any }
        return NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        #endif
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let cont = continuation
        continuation = nil
        self.controller = nil
        onFinish()
        cont?.resume(returning: authorization.credential)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        let cont = continuation
        continuation = nil
        self.controller = nil
        onFinish()
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue
        {
            cont?.resume(throwing: PasskeyPRF.Error.cancelled)
        } else {
            cont?.resume(throwing: PasskeyPRF.Error.failed(error.localizedDescription))
        }
    }
}

import Foundation

/// Form rules for account screens (port of web `account/validation.ts`).
enum PasswordValidation {
    static let minPassword = 10

    static let breachedMessage =
        "This password has appeared in a data breach, so it’s one of the first that attackers try. Choose a different one."

    static func passwordProblem(password: String, confirm: String) -> String? {
        if password.count < minPassword {
            return "Use at least \(minPassword) characters."
        }
        if password != confirm {
            return "The passwords don’t match."
        }
        return nil
    }

    /// `passwordProblem`, then the breached-password check (decision 31).
    static func newPasswordProblem(
        password: String,
        confirm: String,
        session: URLSession = .shared
    ) async -> String? {
        if let problem = passwordProblem(password: password, confirm: confirm) {
            return problem
        }
        return (await BreachCheck.isBreached(password, session: session)) ? breachedMessage : nil
    }
}

import Foundation

/// Pure predicates for the app-switcher / Mission Control privacy cover (PLAN §8.7).
enum PrivacyCoverPolicy {
    /// Phases that show vault contents or recovery words on screen.
    static func isSensitivePhase(_ phase: AppModel.Phase) -> Bool {
        switch phase {
        case .unlocked, .confirmRecovery, .needsRecovery:
            return true
        case .locked, .unlocking, .needsSecondStep, .signup:
            return false
        }
    }

    /// iOS: cover when the scene is not active and the screen is sensitive.
    static func needed(sceneActive: Bool, phase: AppModel.Phase) -> Bool {
        isSensitivePhase(phase) && !sceneActive
    }

    /// macOS: cover when the app resigns active (not mere scene `.inactive`).
    static func needed(macAppActive: Bool, phase: AppModel.Phase) -> Bool {
        isSensitivePhase(phase) && !macAppActive
    }
}

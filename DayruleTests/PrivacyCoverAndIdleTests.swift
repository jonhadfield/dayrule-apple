import Foundation
import Testing
@testable import Dayrule

@Suite("Privacy cover policy")
struct PrivacyCoverPolicyTests {
    @Test("unlocked and recovery phases are sensitive")
    func sensitivePhases() {
        #expect(PrivacyCoverPolicy.isSensitivePhase(.unlocked))
        #expect(PrivacyCoverPolicy.isSensitivePhase(.confirmRecovery))
        #expect(PrivacyCoverPolicy.isSensitivePhase(.needsRecovery))
        #expect(!PrivacyCoverPolicy.isSensitivePhase(.locked))
        #expect(!PrivacyCoverPolicy.isSensitivePhase(.unlocking))
        #expect(!PrivacyCoverPolicy.isSensitivePhase(.needsSecondStep))
        #expect(!PrivacyCoverPolicy.isSensitivePhase(.signup))
    }

    @Test("iOS cover only when inactive and sensitive")
    func iosCover() {
        #expect(PrivacyCoverPolicy.needed(sceneActive: false, phase: .unlocked))
        #expect(!PrivacyCoverPolicy.needed(sceneActive: true, phase: .unlocked))
        #expect(!PrivacyCoverPolicy.needed(sceneActive: false, phase: .locked))
    }

    @Test("Mac cover only when app inactive and sensitive")
    func macCover() {
        #expect(PrivacyCoverPolicy.needed(macAppActive: false, phase: .unlocked))
        #expect(!PrivacyCoverPolicy.needed(macAppActive: true, phase: .unlocked))
        #expect(!PrivacyCoverPolicy.needed(macAppActive: false, phase: .locked))
    }
}

@Suite("Idle auto-lock")
struct IdleAutoLockTests {
    @MainActor
    @Test("noteUserActivity schedules idle when unlocked; sync refresh does not")
    func activitySchedulesIdleSyncDoesNot() async throws {
        try await withMemoryKeychain {
            Primitives.ready()
            let model = AppModel()
            model.stayUnlocked = false
            DeviceUnlockPrefs.stayUnlocked = false

            model.testingSetPhase(.locked)
            model.testingClearIdle()
            model.noteUserActivity()
            #expect(!model.testingIdleTaskActive)

            model.testingSetPhase(.unlocked)
            model.noteUserActivity()
            #expect(model.testingIdleTaskActive)

            model.testingClearIdle()
            #expect(!model.testingIdleTaskActive)
            model.testingEntitiesDidChangeFromSync()
            #expect(!model.testingIdleTaskActive)
        }
    }

    @MainActor
    @Test("stayUnlocked suppresses idle scheduling")
    func stayUnlockedSkipsIdle() async {
        let model = AppModel()
        model.stayUnlocked = true
        DeviceUnlockPrefs.stayUnlocked = true
        defer {
            model.stayUnlocked = false
            DeviceUnlockPrefs.stayUnlocked = false
        }
        model.testingSetPhase(.unlocked)
        model.testingClearIdle()
        model.bumpIdle()
        #expect(!model.testingIdleTaskActive)
    }

    @MainActor
    private func withMemoryKeychain(_ body: () async throws -> Void) async throws {
        let prev = ProcessInfo.processInfo.environment["DAYRULE_MEMORY_KEYCHAIN"]
        setenv("DAYRULE_MEMORY_KEYCHAIN", "1", 1)
        defer {
            if let prev {
                setenv("DAYRULE_MEMORY_KEYCHAIN", prev, 1)
            } else {
                unsetenv("DAYRULE_MEMORY_KEYCHAIN")
            }
            MemoryKeychain.reset()
        }
        MemoryKeychain.reset()
        try await body()
    }
}

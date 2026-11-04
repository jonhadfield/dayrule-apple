import Foundation
import Testing
@testable import Dayrule

@Suite("AppModel lock and BG gateBusy")
struct AppModelLockTests {
    @MainActor
    @Test("await lock() wipes CryptoActor after UI is locked")
    func lockAwaitsCryptoWipe() async throws {
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
        Primitives.ready()

        let model = AppModel()
        let userId = "user-lock-await-0001"
        let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
        _ = try await model.crypto.createLocalDemo(
            password: "password-ok-12",
            userId: userId,
            salt: salt
        )
        #expect(await model.crypto.isUnlocked == true)

        await model.lock()

        #expect(model.phase == .locked)
        #expect(await model.crypto.isUnlocked == false)
    }

    #if os(iOS)
    @MainActor
    @Test("BG reminder refresh no-ops while gateBusy is held")
    func backgroundRefreshRespectsGateBusy() async {
        let stay = DeviceUnlockPrefs.stayUnlocked
        let reminders = DeviceReminderPrefs.enabled
        DeviceUnlockPrefs.stayUnlocked = true
        DeviceReminderPrefs.enabled = true
        defer {
            DeviceUnlockPrefs.stayUnlocked = stay
            DeviceReminderPrefs.enabled = reminders
        }

        let model = AppModel()
        model.testingSetGateBusy(true)
        await model.handleBackgroundReminderRefresh()
        #expect(model.gateBusy == true)
        #expect(model.phase == .locked)
        model.testingSetGateBusy(false)
    }
    #endif
}

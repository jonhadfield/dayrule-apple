import Foundation
import Testing
@testable import Dayrule

@Suite("AppModel lock and BG gateBusy")
struct AppModelLockTests {
    @MainActor
    @Test("await lock() wipes CryptoActor after UI is locked")
    func lockAwaitsCryptoWipe() async throws {
        try await withMemoryKeychain {
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
    }

    @MainActor
    @Test("tryDeviceUnlock no-ops while gateBusy is held")
    func deviceUnlockRespectsGateBusy() async throws {
        try await withMemoryKeychain {
            Primitives.ready()

            let model = AppModel()
            let userId = "user-gate-busy-unlock-0001"
            let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
            let created = try await model.crypto.createLocalDemo(
                password: "password-ok-12",
                userId: userId,
                salt: salt
            )
            await model.crypto.lock()

            let stay = DeviceUnlockPrefs.stayUnlocked
            DeviceUnlockPrefs.stayUnlocked = true
            defer { DeviceUnlockPrefs.stayUnlocked = stay }

            try model.testingSaveCachedAccount(
                SessionStore.CachedAccount(
                    userId: userId,
                    email: "gate-busy@example.com",
                    saltB64: Base64Std.encode(salt),
                    kdf: KdfDTO(v: created.kdf.v, ops: created.kdf.ops, mem: created.kdf.mem),
                    wrappedPassword: WrappedB64(created.wrappedPassword),
                    deviceWrappedAK: WrappedB64(created.wrappedDevice),
                    biometricWrappedAK: nil,
                    passkey: nil
                )
            )

            model.testingSetGateBusy(true)
            await model.tryDeviceUnlock()
            #expect(model.phase == .locked)
            #expect(await model.crypto.isUnlocked == false)
            #expect(model.gateBusy == true)
            model.testingSetGateBusy(false)
        }
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

    @MainActor
    @Test("BG epilogue keeps gateBusy so concurrent unlock cannot zero the AK under unlocked UI")
    func backgroundEpilogueSerializesUnlock() async throws {
        try await withMemoryKeychain {
            Primitives.ready()

            let stay = DeviceUnlockPrefs.stayUnlocked
            let reminders = DeviceReminderPrefs.enabled
            DeviceUnlockPrefs.stayUnlocked = true
            DeviceReminderPrefs.enabled = true
            defer {
                DeviceUnlockPrefs.stayUnlocked = stay
                DeviceReminderPrefs.enabled = reminders
            }

            let model = AppModel()
            let userId = "user-bg-epilogue-0001"
            let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
            let created = try await model.crypto.createLocalDemo(
                password: "password-ok-12",
                userId: userId,
                salt: salt
            )
            await model.crypto.lock()

            try model.testingSaveCachedAccount(
                SessionStore.CachedAccount(
                    userId: userId,
                    email: "bg-epilogue@example.com",
                    saltB64: Base64Std.encode(salt),
                    kdf: KdfDTO(v: created.kdf.v, ops: created.kdf.ops, mem: created.kdf.mem),
                    wrappedPassword: WrappedB64(created.wrappedPassword),
                    deviceWrappedAK: WrappedB64(created.wrappedDevice),
                    biometricWrappedAK: nil,
                    passkey: nil
                )
            )

            var sawGateBusyDuringEpilogue = false
            var concurrentUnlockOpened = false
            model.testingBeforeBackgroundEpilogueLock = {
                sawGateBusyDuringEpilogue = model.gateBusy
                #expect(await model.crypto.isUnlocked == true)
                await model.tryDeviceUnlock()
                concurrentUnlockOpened = model.phase == .unlocked
            }
            defer { model.testingBeforeBackgroundEpilogueLock = nil }

            await model.handleBackgroundReminderRefresh()

            #expect(sawGateBusyDuringEpilogue)
            #expect(!concurrentUnlockOpened)
            #expect(model.phase == .locked)
            #expect(model.gateBusy == false)
            #expect(await model.crypto.isUnlocked == false)
        }
    }
    #endif

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

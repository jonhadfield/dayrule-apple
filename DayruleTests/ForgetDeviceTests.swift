import Foundation
import Testing
@testable import Dayrule

@Suite("forgetDevice (sign-out)")
struct ForgetDeviceTests {
    @Test("device wrap fails after forgetDevice")
    func stayUnlockedCleared() async throws {
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

        let crypto = CryptoActor()
        let userId = "user-forget-0001"
        let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
        let created = try await crypto.createLocalDemo(
            password: "password-ok-12",
            userId: userId,
            salt: salt
        )
        await crypto.lock()
        #expect(await crypto.isUnlocked == false)

        try await crypto.unlockFromDeviceWrap(userId: userId, wrapped: created.wrappedDevice)
        #expect(await crypto.isUnlocked == true)
        await crypto.lock()

        try await crypto.forgetDevice(userId: userId)
        do {
            try await crypto.unlockFromDeviceWrap(userId: userId, wrapped: created.wrappedDevice)
            Issue.record("expected device unlock to fail after forgetDevice")
        } catch {
            #expect(error as? CryptoError == .notUnlocked)
        }
    }
}

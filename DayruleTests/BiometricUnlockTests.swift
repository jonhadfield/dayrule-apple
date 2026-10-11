import Foundation
import Testing
@testable import Dayrule

@Suite("Biometric unlock")
struct BiometricUnlockTests {
    @Test("enable wrap then unlock from biometric Keychain")
    func roundTrip() async throws {
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
        let userId = "user-bio-0001"
        let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
        _ = try await crypto.createLocalDemo(password: "password-ok-12", userId: userId, salt: salt)
        let sealed = try await crypto.enableBiometricWrap()
        await crypto.lock()
        #expect(await crypto.isUnlocked == false)

        try await crypto.unlockFromBiometricWrap(userId: userId, wrapped: sealed)
        #expect(await crypto.isUnlocked == true)
        #expect(await crypto.currentUserId() == userId)

        try await crypto.disableBiometricWrap(userId: userId)
        await crypto.lock()
        do {
            try await crypto.unlockFromBiometricWrap(userId: userId, wrapped: sealed)
            Issue.record("expected unlock to fail after biometric key deleted")
        } catch {
            #expect(error as? CryptoError == .notUnlocked)
        }
    }
}

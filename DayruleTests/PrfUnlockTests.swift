import Foundation
import Testing
@testable import Dayrule

@Suite("PRF unlock")
struct PrfUnlockTests {
    @Test("wrapForPrf / unlockWithPrf round-trip with synthetic PRF")
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
        let userId = "user-prf-0001"
        let salt = Primitives.randomBytes(CryptoConstants.saltBytes)
        _ = try await crypto.createLocalDemo(password: "password-ok-12", userId: userId, salt: salt)

        var secret = Primitives.randomBytes(32)
        let secretCopy = secret
        let wrap = try await crypto.wrapForPrf(prf: &secret)
        #expect(secret.isEmpty)

        await crypto.lock()
        #expect(await crypto.isUnlocked == false)

        var unlockPrf = secretCopy
        try await crypto.unlockWithPrf(userId: userId, prf: &unlockPrf, wrapped: wrap)
        #expect(unlockPrf.isEmpty)
        #expect(await crypto.isUnlocked == true)
        #expect(await crypto.currentUserId() == userId)

        await crypto.lock()
        var wrong = Primitives.randomBytes(32)
        do {
            try await crypto.unlockWithPrf(userId: userId, prf: &wrong, wrapped: wrap)
            Issue.record("expected unwrap failure")
        } catch {
            #expect(error is CryptoError)
        }
    }
}

import Foundation
import Testing
@testable import Dayrule

@Suite("SessionStore")
struct SessionStoreTests {
    @Test("clear removes token and cached account")
    func clearWipesIdentity() throws {
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

        let sessions = SessionStore()
        try sessions.saveToken("bearer-a")
        try sessions.saveAccount(
            SessionStore.CachedAccount(
                userId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                email: "a@example.com",
                saltB64: "AA==",
                kdf: KdfDTO(v: 1, ops: 3, mem: 67_108_864),
                wrappedPassword: WrappedB64(nonce: "n", ciphertext: "c"),
                deviceWrappedAK: nil,
                biometricWrappedAK: nil,
                passkey: nil
            )
        )
        #expect(try sessions.loadToken() == "bearer-a")
        #expect(try sessions.loadAccount()?.email == "a@example.com")

        try sessions.clear()
        #expect(try sessions.loadToken() == nil)
        #expect(try sessions.loadAccount() == nil)
    }

    @Test("leftover Bearer is reused only for the same user")
    func leftoverBearerBinding() {
        let userA = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let userB = "bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
        #expect(SessionBinding.canReuseBearer(unlockedUserId: userA, cachedUserId: userA))
        #expect(SessionBinding.canReuseBearer(unlockedUserId: userA.uppercased(), cachedUserId: userA))
        #expect(!SessionBinding.canReuseBearer(unlockedUserId: userB, cachedUserId: userA))
        #expect(!SessionBinding.canReuseBearer(unlockedUserId: userA, cachedUserId: nil))
        #expect(!SessionBinding.canReuseBearer(unlockedUserId: userA, cachedUserId: ""))
    }
}

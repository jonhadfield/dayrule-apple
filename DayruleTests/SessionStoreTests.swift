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

    @Test("loadSession returns token and account in one snapshot")
    func loadSessionCombines() throws {
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
        try sessions.saveToken("bearer-b")
        try sessions.saveAccount(
            SessionStore.CachedAccount(
                userId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                email: "b@example.com",
                saltB64: "AA==",
                kdf: KdfDTO(v: 1, ops: 3, mem: 67_108_864),
                wrappedPassword: WrappedB64(nonce: "n", ciphertext: "c"),
                deviceWrappedAK: nil,
                biometricWrappedAK: nil,
                passkey: nil
            )
        )
        let snap = try sessions.loadSession()
        #expect(snap.token == "bearer-b")
        #expect(snap.account?.email == "b@example.com")
    }

    @Test("legacy split token+cached migrate into one session item")
    func migratesLegacySplitItems() throws {
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

        let service = "uk.co.lessknown.dayrule.session"
        MemoryKeychain.save(service: service, account: "token", data: Data("legacy-bearer".utf8))
        let account = SessionStore.CachedAccount(
            userId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            email: "legacy@example.com",
            saltB64: "AA==",
            kdf: KdfDTO(v: 1, ops: 3, mem: 67_108_864),
            wrappedPassword: WrappedB64(nonce: "n", ciphertext: "c"),
            deviceWrappedAK: nil,
            biometricWrappedAK: nil,
            passkey: nil
        )
        MemoryKeychain.save(
            service: service,
            account: "cached",
            data: try JSONEncoder().encode(account)
        )

        let sessions = SessionStore()
        let snap = try sessions.loadSession()
        #expect(snap.token == "legacy-bearer")
        #expect(snap.account?.email == "legacy@example.com")
        // Legacy keys removed so a real Keychain would not prompt twice again.
        #expect(MemoryKeychain.load(service: service, account: "token") == nil)
        #expect(MemoryKeychain.load(service: service, account: "cached") == nil)
        #expect(MemoryKeychain.load(service: service, account: "session") != nil)
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

    @Test("loadSession / loadAccount reuse process cache after the first Keychain read")
    func processCacheSkipsRepeatKeychainReads() throws {
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
        try sessions.saveToken("bearer-cache")
        try sessions.saveAccount(
            SessionStore.CachedAccount(
                userId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                email: "cache@example.com",
                saltB64: "AA==",
                kdf: KdfDTO(v: 1, ops: 3, mem: 67_108_864),
                wrappedPassword: WrappedB64(nonce: "n", ciphertext: "c"),
                deviceWrappedAK: nil,
                biometricWrappedAK: nil,
                passkey: nil
            )
        )
        #expect(try sessions.loadToken() == "bearer-cache")
        #expect(try sessions.loadAccount()?.email == "cache@example.com")

        // Wipe the backing store; cached loads must still succeed.
        MemoryKeychain.reset()
        #expect(try sessions.loadToken() == "bearer-cache")
        #expect(try sessions.loadAccount()?.email == "cache@example.com")
        #expect(try sessions.loadSession().token == "bearer-cache")

        try sessions.clear()
        #expect(try sessions.loadToken() == nil)
        #expect(try sessions.loadAccount() == nil)
    }
}

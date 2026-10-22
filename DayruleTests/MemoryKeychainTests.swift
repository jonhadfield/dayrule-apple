import Foundation
import Testing
@testable import Dayrule

struct MemoryKeychainTests {
    @Test("memory Keychain is Debug-only")
    func enabledMatchesConfiguration() {
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
        #if DEBUG
        #expect(MemoryKeychain.enabled)
        unsetenv("DAYRULE_MEMORY_KEYCHAIN")
        #expect(!MemoryKeychain.enabled)
        #else
        #expect(!MemoryKeychain.enabled)
        #endif
    }
}

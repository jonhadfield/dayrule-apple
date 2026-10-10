import Foundation

/// Process-local Keychain stand-in for unsigned e2e / UITest hosts (`DAYRULE_MEMORY_KEYCHAIN=1`).
/// Production never sets that env; SecItem remains the only path.
enum MemoryKeychain {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["DAYRULE_MEMORY_KEYCHAIN"] == "1"
    }

    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        var items: [String: Data] = [:]
    }

    private static let store = Store()

    private static func key(service: String, account: String) -> String {
        service + "\u{0}" + account
    }

    static func save(service: String, account: String, data: Data) {
        store.lock.lock()
        defer { store.lock.unlock() }
        store.items[key(service: service, account: account)] = data
    }

    static func load(service: String, account: String) -> Data? {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.items[key(service: service, account: account)]
    }

    static func delete(service: String, account: String) {
        store.lock.lock()
        defer { store.lock.unlock() }
        store.items.removeValue(forKey: key(service: service, account: account))
    }
}

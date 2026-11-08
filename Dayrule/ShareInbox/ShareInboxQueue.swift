import CryptoKit
import Foundation

/// Append-only encrypted share → Inbox queue in the App Group container.
enum ShareInboxQueue {
    struct Envelope: Codable, Equatable {
        var v: Int
        var id: String
        var createdAt: String
        var nonceB64: String
        var ciphertextB64: String
    }

    /// Encrypt `title` and append to the queue (extension path).
    static func enqueue(title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = try ShareInboxKeyStore.loadOrCreate()
        let sealed = try seal(plaintext: Array(trimmed.utf8), key: key)
        var items = try loadRaw()
        items.append(
            Envelope(
                v: ShareInboxSupport.formatVersion,
                id: UUID().uuidString,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                nonceB64: Data(sealed.nonce).base64EncodedString(),
                ciphertextB64: Data(sealed.ciphertext).base64EncodedString()
            )
        )
        try saveRaw(items)
    }

    /// Decrypt and clear the queue (main app, after unlock).
    static func drainTitles() throws -> [String] {
        let items = try loadRaw()
        guard !items.isEmpty else { return [] }
        let key = try ShareInboxKeyStore.loadOrCreate()
        var titles: [String] = []
        for item in items {
            guard item.v == ShareInboxSupport.formatVersion,
                  let nonce = Data(base64Encoded: item.nonceB64),
                  let ciphertext = Data(base64Encoded: item.ciphertextB64)
            else {
                throw ShareInboxError.corruptQueue
            }
            let plain = try open(
                nonce: Array(nonce),
                ciphertext: Array(ciphertext),
                key: key
            )
            guard let title = String(bytes: plain, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else { continue }
            titles.append(title)
        }
        try saveRaw([])
        return titles
    }

    // MARK: - Crypto (AES-256-GCM; share-queue only)

    private struct Sealed {
        var nonce: [UInt8]
        var ciphertext: [UInt8]
    }

    private static func seal(plaintext: [UInt8], key: [UInt8]) throws -> Sealed {
        guard key.count == 32 else { throw ShareInboxError.crypto }
        let symmetric = SymmetricKey(data: Data(key))
        let sealed = try AES.GCM.seal(Data(plaintext), using: symmetric)
        guard let combined = sealed.combined else { throw ShareInboxError.crypto }
        // combined = nonce (12) || ciphertext+tag
        let nonce = Array(combined.prefix(12))
        let ciphertext = Array(combined.dropFirst(12))
        return Sealed(nonce: nonce, ciphertext: ciphertext)
    }

    private static func open(nonce: [UInt8], ciphertext: [UInt8], key: [UInt8]) throws -> [UInt8] {
        guard key.count == 32, nonce.count == 12 else { throw ShareInboxError.crypto }
        let symmetric = SymmetricKey(data: Data(key))
        var combined = Data(nonce)
        combined.append(Data(ciphertext))
        let sealed = try AES.GCM.SealedBox(combined: combined)
        let plain = try AES.GCM.open(sealed, using: symmetric)
        return Array(plain)
    }

    // MARK: - Persistence

    private static func loadRaw() throws -> [Envelope] {
        guard let url = ShareInboxSupport.queueURL else {
            throw ShareInboxError.containerMissing
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([Envelope].self, from: data)
    }

    private static func saveRaw(_ items: [Envelope]) throws {
        guard let url = ShareInboxSupport.queueURL else {
            throw ShareInboxError.containerMissing
        }
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

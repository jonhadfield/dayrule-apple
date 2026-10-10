import CryptoKit
import Foundation

/// Name-based UUID (RFC 4122 / 9562 v5). Web uses `uuid` package `v5()`.
enum UuidV5 {
    /// Namespace for repeat instance ids (`store/repeats.ts`).
    static let instanceNamespace = UUID(uuidString: "6b0f3c55-2f3e-4f6e-9b39-2b0d9a7e1c41")!

    static func generate(name: String, namespace: UUID = instanceNamespace) -> String {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(Data(name.utf8))
        let digest = Insecure.SHA1.hash(data: data)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let p = Array(hex)
        return String(p[0..<8]) + "-" + String(p[8..<12]) + "-" + String(p[12..<16])
            + "-" + String(p[16..<20]) + "-" + String(p[20..<32])
    }
}

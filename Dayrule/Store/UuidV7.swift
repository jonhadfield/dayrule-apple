import Foundation

/// Time-ordered UUID (RFC 9562 v7). Web store uses `uuid` package `v7()`.
enum UuidV7 {
    /// Lowercase canonical string, suitable for entity ids.
    static func generate(
        nowMs: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
        random: () -> UInt64 = { UInt64.random(in: .min ... .max) }
    ) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        // 48-bit Unix timestamp in milliseconds (big-endian).
        bytes[0] = UInt8((nowMs >> 40) & 0xFF)
        bytes[1] = UInt8((nowMs >> 32) & 0xFF)
        bytes[2] = UInt8((nowMs >> 24) & 0xFF)
        bytes[3] = UInt8((nowMs >> 16) & 0xFF)
        bytes[4] = UInt8((nowMs >> 8) & 0xFF)
        bytes[5] = UInt8(nowMs & 0xFF)

        let r1 = random()
        let r2 = random()
        // rand_a (12 bits) + version 7
        bytes[6] = UInt8(0x70 | ((r1 >> 8) & 0x0F))
        bytes[7] = UInt8(r1 & 0xFF)
        // variant 10xx + rand_b
        bytes[8] = UInt8(0x80 | ((r2 >> 56) & 0x3F))
        bytes[9] = UInt8((r2 >> 48) & 0xFF)
        bytes[10] = UInt8((r2 >> 40) & 0xFF)
        bytes[11] = UInt8((r2 >> 32) & 0xFF)
        bytes[12] = UInt8((r2 >> 24) & 0xFF)
        bytes[13] = UInt8((r2 >> 16) & 0xFF)
        bytes[14] = UInt8((r2 >> 8) & 0xFF)
        bytes[15] = UInt8(r2 & 0xFF)

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let p = Array(hex)
        return String(p[0..<8]) + "-" + String(p[8..<12]) + "-" + String(p[12..<16])
            + "-" + String(p[16..<20]) + "-" + String(p[20..<32])
    }
}

import Testing
@testable import Dayrule

@Suite("UuidV7")
struct UuidV7Tests {
    @Test func versionAndVariantBits() {
        let id = UuidV7.generate(nowMs: 1_700_000_000_000) { 0x0123_4567_89AB_CDEF }
        let hex = id.replacingOccurrences(of: "-", with: "")
        #expect(hex.count == 32)
        // Version nibble is the high nibble of byte 6 → character index 12.
        #expect(hex[hex.index(hex.startIndex, offsetBy: 12)] == "7")
        // Variant: byte 8 high bits 10xx → char index 16 is 8, 9, a, or b.
        let variant = hex[hex.index(hex.startIndex, offsetBy: 16)]
        #expect(["8", "9", "a", "b"].contains(variant))
        #expect(id == id.lowercased())
    }

    @Test func timestampsOrderLexicographically() {
        let a = UuidV7.generate(nowMs: 1_700_000_000_000) { 0 }
        let b = UuidV7.generate(nowMs: 1_700_000_000_001) { 0 }
        #expect(a < b)
    }
}

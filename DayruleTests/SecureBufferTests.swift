import Foundation
import Testing
@testable import Dayrule

@Suite("SecureBuffer")
struct SecureBufferTests {
    @Test("withUnsafeBytes borrows the same bytes without a public heap copy API")
    func borrowsBytes() {
        Primitives.ready()
        let expected: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]
        let buffer = SecureBuffer(bytes: expected)
        let seen = buffer.withUnsafeBytes { Array($0) }
        #expect(seen == expected)
        #expect(!buffer.isEmpty)
    }

    @Test("clear zeros and frees; subsequent borrow is empty")
    func clearEmpties() {
        Primitives.ready()
        let buffer = SecureBuffer(bytes: Array(repeating: 0xAB, count: 32))
        buffer.clear()
        #expect(buffer.isEmpty)
        let seen = buffer.withUnsafeBytes { Array($0) }
        #expect(seen.isEmpty)
    }

    @Test("SecureBuffer.swift exposes withUnsafeBytes, not a bytes heap getter")
    func noBytesHeapGetterInSource() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Dayrule/Crypto/SecureBuffer.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("func withUnsafeBytes"))
        #expect(!source.contains("var bytes"))
        #expect(!source.contains("func bytes"))
        #expect(!source.contains("-> [UInt8]"))
    }
}

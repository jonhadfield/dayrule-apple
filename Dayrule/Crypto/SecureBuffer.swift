import Clibsodium
import Foundation

/// Key material in `sodium_malloc` memory; zeroed on `clear()`.
final class SecureBuffer: @unchecked Sendable {
    private var pointer: UnsafeMutableRawPointer?
    private let count: Int

    init(bytes: [UInt8]) {
        precondition(bytes.count > 0)
        // sodium_malloc aborts if sodium_init() has not run (libsodium assert).
        Primitives.ready()
        count = bytes.count
        guard let ptr = sodium_malloc(count) else {
            preconditionFailure("sodium_malloc failed")
        }
        ptr.copyMemory(from: bytes, byteCount: count)
        pointer = ptr
    }

    deinit {
        clear()
    }

    var bytes: [UInt8] {
        guard let pointer else { return [] }
        return Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }

    func clear() {
        guard let pointer else { return }
        sodium_memzero(pointer, count)
        sodium_free(pointer)
        self.pointer = nil
    }
}

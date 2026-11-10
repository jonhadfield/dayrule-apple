import Clibsodium
import Foundation

/// Key material in `sodium_malloc` memory; zeroed on `clear()`.
/// Callers borrow bytes via `withUnsafeBytes` — never copy into a long-lived
/// `[UInt8]` heap buffer (PLAN decision 60).
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

    /// Borrow the key bytes without copying into a managed `Array`.
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        guard let pointer else {
            return try body(UnsafeRawBufferPointer(start: nil, count: 0))
        }
        return try body(UnsafeRawBufferPointer(start: pointer, count: count))
    }

    var isEmpty: Bool { pointer == nil || count == 0 }

    func clear() {
        guard let pointer else { return }
        sodium_memzero(pointer, count)
        sodium_free(pointer)
        self.pointer = nil
    }
}

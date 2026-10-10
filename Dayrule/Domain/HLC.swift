import Foundation

/// Hybrid logical clock (web `domain/hlc.ts`, PLAN §11.2).
/// Stamps compare as plain strings: wall (base36), counter, device id.
struct HLC: Sendable {
    typealias Stamp = String

    private var wall = 0
    private var counter = 0
    private let device: String
    private let now: @Sendable () -> Int

    init(device: String, now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }) {
        precondition(device.range(of: "^[a-z0-9]{1,16}$", options: .regularExpression) != nil)
        self.device = device
        self.now = now
    }

    mutating func tick() -> Stamp {
        let t = now()
        if t > wall {
            wall = t
            counter = 0
        } else {
            counter += 1
        }
        return "\(pad(wall, 9))-\(pad(counter, 4))-\(device)"
    }

    mutating func observe(_ stamp: Stamp) {
        let parts = stamp.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        let w = Int(parts.first.map(String.init) ?? "0", radix: 36) ?? 0
        let c = Int(parts.dropFirst().first.map(String.init) ?? "0", radix: 36) ?? 0
        if w > wall || (w == wall && c > counter) {
            wall = w
            counter = c
        }
    }

    private func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n, radix: 36)
        if s.count >= width { return s }
        return String(repeating: "0", count: width - s.count) + s
    }
}

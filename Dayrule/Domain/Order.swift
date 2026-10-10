import Foundation

typealias OrderKey = String

/// Fractional ordering wrappers (web `domain/order.ts`).
enum Order {
    static func compareKeys(_ a: OrderKey, _ b: OrderKey) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        return 0
    }

    static func keyBetween(_ before: OrderKey?, _ after: OrderKey?) throws -> OrderKey {
        try FractionalIndexing.generateKeyBetween(before, after)
    }

    static func keysBetween(_ before: OrderKey?, _ after: OrderKey?, _ n: Int) throws -> [OrderKey] {
        try FractionalIndexing.generateNKeysBetween(before, after, n)
    }

    static func keyAfterLast(_ keys: [OrderKey]) throws -> OrderKey {
        let last = keys.max()
        return try keyBetween(last, nil)
    }
}

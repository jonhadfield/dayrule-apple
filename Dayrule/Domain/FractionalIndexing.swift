import Foundation

/// Exact port of npm fractional-indexing v4 default alphabet behaviour (CC0).
/// Default: digits = BASE_62, intDigits = BASE_52 → keys like "a0", "a1", "a0V".
enum FractionalIndexing {
    static let base62Digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    static let base52Digits = String(base62Digits.dropFirst(10))

    enum Error: Swift.Error, LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let s): s
            }
        }
    }

    private static func getDigitIndex(_ digits: String) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: 256)
        for (i, ch) in digits.utf8.enumerated() {
            m[Int(ch)] = UInt8(i)
        }
        return m
    }

    private static func charAt(_ s: String, _ i: Int) -> Character? {
        guard i >= 0, i < s.count else { return nil }
        return s[s.index(s.startIndex, offsetBy: i)]
    }

    private static func codeUnit(_ s: String, _ i: Int) -> UInt8 {
        Array(s.utf8)[i]
    }

    private static func midpointJS(_ a: String, _ b: String?, _ digits: String, _ lookup: [UInt8]) throws -> String {
        let zeroChar = digits[digits.startIndex]
        let zero = String(zeroChar)
        if let b, a >= b { throw Error.message("\(a) >= \(b)") }
        if (!a.isEmpty && String(a.last!) == zero) || (b != nil && !b!.isEmpty && String(b!.last!) == zero) {
            throw Error.message("trailing zero")
        }
        if let b {
            var n = 0
            while true {
                let aCh = n < a.count ? String(charAt(a, n)!) : zero
                guard n < b.count else { break }
                let bCh = String(charAt(b, n)!)
                if aCh != bCh { break }
                n += 1
            }
            if n > 0 {
                let aRest = n < a.count ? String(a[a.index(a.startIndex, offsetBy: n)...]) : ""
                let bRest = n < b.count ? String(b[b.index(b.startIndex, offsetBy: n)...]) : ""
                return String(b.prefix(n)) + (try midpointJS(aRest, bRest.isEmpty ? nil : bRest, digits, lookup))
            }
        }
        let digitA = a.isEmpty ? 0 : Int(lookup[Int(codeUnit(a, 0))])
        let digitB = b != nil ? Int(lookup[Int(codeUnit(b!, 0))]) : digits.count
        if digitB - digitA > 1 {
            // JS Math.round: half away from zero.
            let midDigit = Int((0.5 * Double(digitA + digitB)).rounded(.toNearestOrAwayFromZero))
            return String(charAt(digits, midDigit)!)
        } else {
            if let b, b.count > 1 {
                return String(b.prefix(1))
            } else {
                return String(charAt(digits, digitA)!) + (try midpointJS(String(a.dropFirst()), nil, digits, lookup))
            }
        }
    }

    private static func getIntegerLength(_ head: Character, _ intDigits: String, _ intLookup: [UInt8]) throws -> Int {
        let headStr = String(head)
        let i = Int(intLookup[Int(headStr.utf8.first!)])
        if charAt(intDigits, i) == head {
            let half = intDigits.count / 2
            return i < half ? half - i + 1 : i - half + 2
        }
        throw Error.message("invalid order key head: \(head)")
    }

    private static func getIntegerPart(_ key: String, _ intDigits: String, _ intLookup: [UInt8]) throws -> String {
        let len = try getIntegerLength(key[key.startIndex], intDigits, intLookup)
        if len > key.count { throw Error.message("invalid order key: \(key)") }
        return String(key.prefix(len))
    }

    private static func isSmallestInteger(_ key: String, _ digits: String, _ intDigits: String) -> Bool {
        let zeros = String(repeating: String(digits[digits.startIndex]), count: intDigits.count / 2)
        let smallest = String(intDigits[intDigits.startIndex]) + zeros
        return key == smallest
    }

    private static func validateOrderKey(_ key: String, _ digits: String, _ intDigits: String, _ intLookup: [UInt8]) throws {
        if isSmallestInteger(key, digits, intDigits) {
            throw Error.message("invalid order key: \(key)")
        }
        let i = try getIntegerPart(key, intDigits, intLookup)
        let f = String(key.dropFirst(i.count))
        if let last = f.last, String(last) == String(digits[digits.startIndex]) {
            throw Error.message("invalid order key: \(key)")
        }
    }

    private static func validateInteger(_ int: String, _ intDigits: String, _ intLookup: [UInt8]) throws {
        let len = try getIntegerLength(int[int.startIndex], intDigits, intLookup)
        if int.count != len {
            throw Error.message("invalid integer part of order key: \(int)")
        }
    }

    private static func incrementInteger(
        _ x: String, _ digits: String, _ lookup: [UInt8], _ intDigits: String, _ intLookup: [UInt8]
    ) throws -> String? {
        try validateInteger(x, intDigits, intLookup)
        let head = String(x[x.startIndex])
        let zero = String(digits[digits.startIndex])
        var trailing = ""
        let xArr = Array(x)
        for i in stride(from: xArr.count - 1, through: 1, by: -1) {
            let d = Int(lookup[Int(String(xArr[i]).utf8.first!)]) + 1
            if d == digits.count {
                trailing = zero + trailing
            } else {
                let mid = String(xArr[1..<i])
                return head + mid + String(charAt(digits, d)!) + trailing
            }
        }
        let headIndex = Int(intLookup[Int(head.utf8.first!)])
        if headIndex == intDigits.count - 1 { return nil }
        let h = String(charAt(intDigits, headIndex + 1)!)
        let lengthDelta =
            (try getIntegerLength(h[h.startIndex], intDigits, intLookup))
            - (try getIntegerLength(head[head.startIndex], intDigits, intLookup))
        if lengthDelta > 0 { return h + trailing + zero }
        if lengthDelta < 0 { return h + String(trailing.dropFirst()) }
        return h + trailing
    }

    private static func decrementInteger(
        _ x: String, _ digits: String, _ lookup: [UInt8], _ intDigits: String, _ intLookup: [UInt8]
    ) throws -> String? {
        try validateInteger(x, intDigits, intLookup)
        let head = String(x[x.startIndex])
        let last = String(digits[digits.index(before: digits.endIndex)])
        var trailing = ""
        let xArr = Array(x)
        for i in stride(from: xArr.count - 1, through: 1, by: -1) {
            let d = Int(lookup[Int(String(xArr[i]).utf8.first!)]) - 1
            if d == -1 {
                trailing = last + trailing
            } else {
                let mid = String(xArr[1..<i])
                return head + mid + String(charAt(digits, d)!) + trailing
            }
        }
        let headIndex = Int(intLookup[Int(head.utf8.first!)])
        if headIndex == 0 { return nil }
        let h = String(charAt(intDigits, headIndex - 1)!)
        let lengthDelta =
            (try getIntegerLength(h[h.startIndex], intDigits, intLookup))
            - (try getIntegerLength(head[head.startIndex], intDigits, intLookup))
        if lengthDelta > 0 { return h + trailing + last }
        if lengthDelta < 0 { return h + String(trailing.dropFirst()) }
        return h + trailing
    }

    private static func isStrictlyAscending(_ s: String) -> Bool {
        let codes = Array(s.utf8)
        for i in 1..<codes.count where codes[i - 1] >= codes[i] { return false }
        return true
    }

    private static func validateDigits(_ digits: String) throws {
        guard digits.count >= 2, isStrictlyAscending(digits) else {
            throw Error.message("digits must be at least 2 characters in strictly ascending character code order: \(digits)")
        }
    }

    private static func validateIntDigits(_ intDigits: String) throws {
        guard intDigits.count >= 2, intDigits.count % 2 == 0, isStrictlyAscending(intDigits) else {
            throw Error.message("intDigits must be an even number of at least 2 characters in strictly ascending character code order: \(intDigits)")
        }
    }

    static func generateKeyBetween(_ a: String?, _ b: String?, digits: String? = nil, intDigits: String? = nil) throws -> String {
        var intD = intDigits
        var dig = digits
        if let intD {
            try validateIntDigits(intD)
        } else {
            intD = dig ?? base52Digits
        }
        if let dig {
            try validateDigits(dig)
        } else {
            dig = base62Digits
        }
        let digits = dig!
        let intDigits = intD!
        let lookup = getDigitIndex(digits)
        let intLookup = getDigitIndex(intDigits)
        var a = a
        var b = b
        if let a { try validateOrderKey(a, digits, intDigits, intLookup) }
        if let b { try validateOrderKey(b, digits, intDigits, intLookup) }
        if let aa = a, let bb = b, aa > bb {
            a = bb
            b = aa
        }
        if a == nil {
            if b == nil {
                let head = charAt(intDigits, intDigits.count / 2)!
                return String(head) + String(digits[digits.startIndex])
            }
            let ib = try getIntegerPart(b!, intDigits, intLookup)
            let fb = String(b!.dropFirst(ib.count))
            if isSmallestInteger(ib, digits, intDigits) {
                return ib + (try midpointJS("", fb, digits, lookup))
            }
            if ib < b! { return ib }
            guard let res = try decrementInteger(ib, digits, lookup, intDigits, intLookup) else {
                throw Error.message("cannot decrement any more")
            }
            return res
        }
        if b == nil {
            let ia = try getIntegerPart(a!, intDigits, intLookup)
            let fa = String(a!.dropFirst(ia.count))
            if let i = try incrementInteger(ia, digits, lookup, intDigits, intLookup) {
                return i
            }
            return ia + (try midpointJS(fa, nil, digits, lookup))
        }
        let ia = try getIntegerPart(a!, intDigits, intLookup)
        let fa = String(a!.dropFirst(ia.count))
        let ib = try getIntegerPart(b!, intDigits, intLookup)
        let fb = String(b!.dropFirst(ib.count))
        if ia == ib {
            return ia + (try midpointJS(fa, fb, digits, lookup))
        }
        guard let i = try incrementInteger(ia, digits, lookup, intDigits, intLookup) else {
            throw Error.message("cannot increment any more")
        }
        if i < b! { return i }
        return ia + (try midpointJS(fa, nil, digits, lookup))
    }

    static func generateNKeysBetween(_ a: String?, _ b: String?, _ n: Int, digits: String? = nil, intDigits: String? = nil) throws -> [String] {
        var intD = intDigits
        var dig = digits
        if let intD {
            try validateIntDigits(intD)
        } else {
            intD = dig ?? base52Digits
        }
        if let dig {
            try validateDigits(dig)
        } else {
            dig = base62Digits
        }
        let digits = dig!
        let intDigits = intD!
        if n == 0 { return [] }
        if n == 1 { return [try generateKeyBetween(a, b, digits: digits, intDigits: intDigits)] }
        if b == nil {
            var c = try generateKeyBetween(a, b, digits: digits, intDigits: intDigits)
            var result = [c]
            for _ in 0..<(n - 1) {
                c = try generateKeyBetween(c, b, digits: digits, intDigits: intDigits)
                result.append(c)
            }
            return result
        }
        if a == nil {
            var c = try generateKeyBetween(a, b, digits: digits, intDigits: intDigits)
            var result = [c]
            for _ in 0..<(n - 1) {
                c = try generateKeyBetween(a, c, digits: digits, intDigits: intDigits)
                result.append(c)
            }
            return result.reversed()
        }
        let mid = n / 2
        let c = try generateKeyBetween(a, b, digits: digits, intDigits: intDigits)
        return try generateNKeysBetween(a, c, mid, digits: digits, intDigits: intDigits)
            + [c]
            + generateNKeysBetween(c, b, n - mid - 1, digits: digits, intDigits: intDigits)
    }
}

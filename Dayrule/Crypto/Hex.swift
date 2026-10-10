import Foundation

enum Hex {
    static func encode(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ hex: String) throws -> [UInt8] {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleaned.count.isMultiple(of: 2) else { throw CryptoError.openFailed }
        var out: [UInt8] = []
        out.reserveCapacity(cleaned.count / 2)
        var i = cleaned.startIndex
        while i < cleaned.endIndex {
            let j = cleaned.index(i, offsetBy: 2)
            guard let b = UInt8(cleaned[i..<j], radix: 16) else { throw CryptoError.openFailed }
            out.append(b)
            i = j
        }
        return out
    }
}

enum Base64Std {
    static func encode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
    }

    static func decode(_ s: String) throws -> [UInt8] {
        guard let data = Data(base64Encoded: s) else { throw CryptoError.openFailed }
        return [UInt8](data)
    }
}

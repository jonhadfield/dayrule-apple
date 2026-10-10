import Foundation

enum Recovery {
    static func newEntropy() -> [UInt8] {
        Primitives.randomBytes(CryptoConstants.keyBytes)
    }

    static func toPhrase(_ entropy: [UInt8]) throws -> [String] {
        try BIP39.toPhrase(entropy: entropy)
    }

    static func fromPhrase(_ words: String) throws -> [UInt8] {
        try BIP39.fromPhrase(words)
    }

    static func recoveryKey(entropy: [UInt8]) -> [UInt8] {
        Primitives.hkdf(ikm: entropy, label: Labels.recovery)
    }

    static func recoveryProof(entropy: [UInt8]) -> [UInt8] {
        Primitives.hkdf(ikm: entropy, label: Labels.recoveryProof)
    }
}

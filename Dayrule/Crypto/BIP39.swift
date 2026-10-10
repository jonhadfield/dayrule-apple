import CryptoKit
import Foundation

/// BIP39 English mnemonic over raw entropy (never `mnemonicToSeed` / PBKDF2).
enum BIP39 {
    private static let wordlist = BIP39Wordlist.english

    static func toPhrase(entropy: [UInt8]) throws -> [String] {
        guard entropy.count == 32 else { throw CryptoError.recoveryPhraseInvalid }
        guard wordlist.count == 2048 else { throw CryptoError.recoveryPhraseInvalid }

        let hash = Array(SHA256.hash(data: Data(entropy)))
        let checksumBits = 8 // 256-bit entropy → 8 checksum bits
        var bits = ""
        for b in entropy {
            bits += String(b, radix: 2).leftPad(to: 8, with: "0")
        }
        bits += String(hash[0], radix: 2).leftPad(to: 8, with: "0").prefix(checksumBits)

        var words: [String] = []
        words.reserveCapacity(24)
        var i = bits.startIndex
        while i < bits.endIndex {
            let j = bits.index(i, offsetBy: 11, limitedBy: bits.endIndex) ?? bits.endIndex
            let chunk = String(bits[i..<j])
            guard let idx = Int(chunk, radix: 2), idx < wordlist.count else {
                throw CryptoError.recoveryPhraseInvalid
            }
            words.append(wordlist[idx])
            i = j
        }
        return words
    }

    static func fromPhrase(_ words: String) throws -> [UInt8] {
        let phrase = words.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let parts = phrase.split(separator: " ").map(String.init)
        guard parts.count == 24 else { throw CryptoError.recoveryPhraseInvalid }
        guard wordlist.count == 2048 else { throw CryptoError.recoveryPhraseInvalid }

        var bits = ""
        for w in parts {
            guard let idx = wordlist.firstIndex(of: w) else { throw CryptoError.recoveryPhraseInvalid }
            bits += String(idx, radix: 2).leftPad(to: 11, with: "0")
        }

        let entropyBits = String(bits.prefix(256))
        let checksumBits = String(bits.suffix(8))
        var entropy = [UInt8]()
        entropy.reserveCapacity(32)
        var i = entropyBits.startIndex
        while i < entropyBits.endIndex {
            let j = entropyBits.index(i, offsetBy: 8)
            guard let b = UInt8(entropyBits[i..<j], radix: 2) else { throw CryptoError.recoveryPhraseInvalid }
            entropy.append(b)
            i = j
        }

        let hash = Array(SHA256.hash(data: Data(entropy)))
        let expected = String(hash[0], radix: 2).leftPad(to: 8, with: "0").prefix(8)
        guard checksumBits == expected else { throw CryptoError.recoveryPhraseInvalid }
        return entropy
    }
}

private extension String {
    func leftPad(to length: Int, with pad: Character) -> String {
        if count >= length { return self }
        return String(repeating: pad, count: length - count) + self
    }
}

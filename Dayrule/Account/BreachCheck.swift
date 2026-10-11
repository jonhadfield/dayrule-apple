import CryptoKit
import Foundation

/// Have I Been Pwned range API (web decision 31 / PLAN §8).
/// Only the first 5 hex chars of SHA-1 leave the device; fails open on any error.
enum BreachCheck {
    static let rangeURL = "https://api.pwnedpasswords.com/range/"
    static let defaultTimeoutMs = 3000

    /// True if the password is in a known breach; false if not, or if unknown.
    static func isBreached(
        _ password: String,
        timeoutMs: Int = defaultTimeoutMs,
        session: URLSession = .shared
    ) async -> Bool {
        do {
            let hash = sha1Hex(password)
            let prefix = String(hash.prefix(5))
            let suffix = String(hash.dropFirst(5))
            guard let url = URL(string: rangeURL + prefix) else { return false }

            var req = URLRequest(url: url, timeoutInterval: Double(timeoutMs) / 1000)
            req.setValue("true", forHTTPHeaderField: "Add-Padding")
            req.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return false }

            let body = String(decoding: data, as: UTF8.self)
            return body.split(whereSeparator: \.isNewline).contains { line in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { return false }
                let s = parts[0].trimmingCharacters(in: .whitespaces)
                let count = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                return s.caseInsensitiveCompare(suffix) == .orderedSame && count > 0
            }
        } catch {
            return false
        }
    }

    static func sha1Hex(_ text: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}

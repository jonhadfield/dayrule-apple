import Foundation

enum ISOStamp {
    /// JavaScript `toISOString()` form with milliseconds (PLAN §5.3).
    static func format(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let s = f.string(from: date)
        // Some Foundation builds omit fractional seconds; force `.SSS`.
        if s.contains(".") { return s }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        plain.timeZone = TimeZone(secondsFromGMT: 0)
        let base = plain.string(from: date) // …Z
        let ms = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        return base.replacingOccurrences(of: "Z", with: String(format: ".%03dZ", ms))
    }
}

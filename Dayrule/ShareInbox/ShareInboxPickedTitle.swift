import Foundation

/// Pure title selection for Share sheet payloads (PLAN decision 39).
/// URL wins over plain text; attributed content is the last resort.
enum ShareInboxPickedTitle {
    /// Resolve a title from already-loaded attachment payloads.
    /// Empty / whitespace-only strings are ignored at each layer.
    static func resolve(
        urlString: String? = nil,
        plainText: String? = nil,
        attributedText: String? = nil
    ) -> String {
        if let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return urlString
        }
        if let plainText {
            let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return plainText }
        }
        if let attributedText {
            let trimmed = attributedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return attributedText }
        }
        return ""
    }
}

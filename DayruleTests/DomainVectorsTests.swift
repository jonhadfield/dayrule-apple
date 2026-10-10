import Foundation
import Testing

/// Smoke-load the mirrored domain vectors (PLAN §16 / M3 entry).
/// Behaviour ports land with M3; this only proves the fixture is present.
struct DomainVectorsTests {
    @Test("docs/shared/domain-vectors.json is mirrored")
    func loadMirror() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/shared/domain-vectors.json")
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 1)
        let parseWhen = obj?["parseWhen"] as? [Any]
        #expect((parseWhen?.count ?? 0) >= 20)
        #expect(obj?["order"] != nil)
        #expect(obj?["hlc"] != nil)
    }
}

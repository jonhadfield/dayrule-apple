import Foundation
import Testing
@testable import Dayrule

/// Known-answer domain vectors (PLAN §16 / M3).
@Suite("Domain vectors")
struct DomainVectorsTests {
    private struct File: Decodable {
        var version: Int
        var parseWhen: [WhenCase]
        var order: OrderSection
        var hlc: HlcSection
        var merge: MergeSection?
    }

    private struct MergeSection: Decodable {
        var triples: [MergeTriple]
        var tombstones: [TombstoneCase]
        var latestStamp: [LatestStampCase]
    }

    private struct MergeTriple: Decodable {
        var local: AnyJSON?
        var remote: AnyJSON
        var result: AnyJSON
    }

    private struct TombstoneCase: Decodable {
        var entity: AnyJSON?
        var tombstone: String
        var result: TombstoneResultDTO
    }

    private struct TombstoneResultDTO: Decodable {
        var kind: String
        var value: AnyJSON?
    }

    private struct LatestStampCase: Decodable {
        var entity: AnyJSON
        var result: String
    }

    /// Opaque JSON object for merge fixtures.
    private struct AnyJSON: Decodable, Equatable {
        var value: Any

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let obj = try? c.decode([String: AnyJSON].self) {
                value = obj.mapValues(\.value)
            } else if let arr = try? c.decode([AnyJSON].self) {
                value = arr.map(\.value)
            } else if let s = try? c.decode(String.self) {
                value = s
            } else if let b = try? c.decode(Bool.self) {
                value = b
            } else if let i = try? c.decode(Int.self) {
                value = i
            } else if let d = try? c.decode(Double.self) {
                value = d
            } else if c.decodeNil() {
                value = NSNull()
            } else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON")
            }
        }

        static func == (lhs: AnyJSON, rhs: AnyJSON) -> Bool {
            jsonEquals(lhs.value, rhs.value)
        }

        var dictionary: [String: Any]? { value as? [String: Any] }
    }

    private static func jsonEquals(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as String, y as String): x == y
        case let (x as Bool, y as Bool): x == y
        case let (x as Int, y as Int): x == y
        case let (x as Double, y as Double): x == y
        case (is NSNull, is NSNull): true
        case let (x as [String: Any], y as [String: Any]):
            x.keys == y.keys && x.keys.allSatisfy { jsonEquals(x[$0] as Any, y[$0] as Any) }
        case let (x as [Any], y as [Any]):
            x.count == y.count && zip(x, y).allSatisfy { jsonEquals($0, $1) }
        default:
            false
        }
    }

    private struct WhenCase: Decodable {
        var input: String
        var today: String
        var result: WhenDTO?
    }

    private struct WhenDTO: Decodable, Equatable {
        var kind: String
        var date: String?
    }

    private struct OrderSection: Decodable {
        var keyBetween: [KeyBetweenCase]
        var keysBetween: [KeysBetweenCase]
        var compare: [CompareCase]
    }

    private struct KeyBetweenCase: Decodable {
        var before: String?
        var after: String?
        var result: String
    }

    private struct KeysBetweenCase: Decodable {
        var before: String?
        var after: String?
        var n: Int
        var result: [String]
    }

    private struct CompareCase: Decodable {
        var a: String
        var b: String
        var result: Int
    }

    private struct HlcSection: Decodable {
        var device: String
        var steps: [HlcStep]
    }

    private struct HlcStep: Decodable {
        var op: String
        var now: Int?
        var stamp: String?
        var result: String?
    }

    private func load() throws -> File {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/shared/domain-vectors.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    private func localDay(_ iso: String) -> Date {
        When.fromLocalDate(iso)!
    }

    @Test("parseWhen matches shared vectors")
    func parseWhenVectors() throws {
        let file = try load()
        for c in file.parseWhen {
            let got = When.parseWhen(c.input, today: localDay(c.today))
            let dto: WhenDTO? = {
                guard let got else { return nil }
                switch got {
                case .today: return WhenDTO(kind: "today", date: nil)
                case .later: return WhenDTO(kind: "later", date: nil)
                case .date(let d): return WhenDTO(kind: "date", date: d)
                }
            }()
            #expect(dto == c.result, "parseWhen(\(c.input), \(c.today))")
        }
    }

    @Test("order keys match shared vectors")
    func orderVectors() throws {
        let file = try load()
        for c in file.order.keyBetween {
            let got = try Order.keyBetween(c.before, c.after)
            #expect(got == c.result)
        }
        for c in file.order.keysBetween {
            let got = try Order.keysBetween(c.before, c.after, c.n)
            #expect(got == c.result)
        }
        for c in file.order.compare {
            #expect(Order.compareKeys(c.a, c.b) == c.result)
        }
    }

    @Test("HLC tick/observe matches shared vectors")
    func hlcVectors() throws {
        final class NowBox: @unchecked Sendable { var value = 0 }
        let file = try load()
        let box = NowBox()
        var clock = HLC(device: file.hlc.device, now: { box.value })
        for step in file.hlc.steps {
            switch step.op {
            case "tick":
                box.value = step.now!
                let stamp = clock.tick()
                #expect(stamp == step.result)
            case "observe":
                clock.observe(step.stamp!)
            default:
                Issue.record("unknown HLC op \(step.op)")
            }
        }
    }

    @Test("mergeEntity and tombstones match shared vectors")
    func mergeVectors() throws {
        let file = try load()
        #expect(file.version == 2)
        let merge = try #require(file.merge)
        for t in merge.triples {
            let got = Merge.mergeEntity(local: t.local?.dictionary, remote: t.remote.dictionary!)
            #expect(Self.jsonEquals(got, t.result.value))
        }
        for t in merge.tombstones {
            let got = Merge.resolveTombstone(entity: t.entity?.dictionary, tombstone: t.tombstone)
            switch (got, t.result.kind) {
            case (.delete, "delete"):
                break
            case (.keep(let v), "keep"):
                #expect(Self.jsonEquals(v, t.result.value!.value))
            default:
                Issue.record("tombstone mismatch \(t.tombstone)")
            }
        }
        for t in merge.latestStamp {
            let clock = t.entity.dictionary?["clock"] as? FieldClock
            #expect(Merge.latestStamp(clock) == t.result)
        }
    }
}

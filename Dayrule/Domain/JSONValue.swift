import Foundation

/// JSON tree for unknown entity fields (PLAN §5.3).
enum JSONValue: Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    static func fromAny(_ any: Any) -> JSONValue {
        switch any {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let n as Int: return .number(Double(n))
        case let n as Double: return .number(n)
        case let n as NSNumber:
            // JSONSerialization bridges bools to NSNumber; CFBoolean catches them.
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let dict as [String: Any]:
            return .object(dict.mapValues(fromAny))
        case let arr as [Any]:
            return .array(arr.map(fromAny))
        case is NSNull:
            return .null
        default:
            return .null
        }
    }

    func toAny() -> Any {
        switch self {
        case .object(let o): o.mapValues { $0.toAny() }
        case .array(let a): a.map { $0.toAny() }
        case .string(let s): s
        case .number(let n):
            n.rounded() == n && n >= Double(Int.min) && n <= Double(Int.max)
                ? Int(n) : n
        case .bool(let b): b
        case .null: NSNull()
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

enum JSONDict {
    static func fromAny(_ any: [String: Any]) -> [String: JSONValue] {
        any.mapValues(JSONValue.fromAny)
    }

    static func toAny(_ dict: [String: JSONValue]) -> [String: Any] {
        dict.mapValues { $0.toAny() }
    }
}

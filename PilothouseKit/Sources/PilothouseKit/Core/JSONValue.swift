import Foundation

/// A lossless, Sendable JSON tree. Used to round-trip *arr resources on edit so
/// that fields this app does not model are never dropped on PUT.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n.rounded() == n, abs(n) < 9.0e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        get { if case .object(let o) = self { return o[key] }; return nil }
        set {
            guard case .object(var o) = self else { return }
            o[key] = newValue
            self = .object(o)
        }
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.rounded() == n ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    public var intValue: Int? { doubleValue.map { Int($0) } }
    public var int64Value: Int64? { doubleValue.map { Int64($0) } }
    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return s == "true" || s == "1"
        default: return nil
        }
    }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    public init(_ v: Bool) { self = .bool(v) }
    public init(_ v: Int) { self = .number(Double(v)) }
    public init(_ v: Int64) { self = .number(Double(v)) }
    public init(_ v: Double) { self = .number(v) }
    public init(_ v: String) { self = .string(v) }
    public init(_ v: [Int]) { self = .array(v.map { JSONValue($0) }) }

    /// Decode a typed model from this tree.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONCoding.decoder.decode(T.self, from: JSONCoding.encoder.encode(self))
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
    public init(nilLiteral: ()) { self = .null }
}

public enum JSONCoding {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                if let date = parseDate(s) { return date }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
            }
            if let t = try? c.decode(Double.self) { return Date(timeIntervalSince1970: t) }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date")
        }
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static func parseDate(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle()) { return d }
        // Date only (yyyy-MM-dd)
        if s.count == 10, let d = try? Date(s, strategy: Date.ISO8601FormatStyle().year().month().day()) { return d }
        // Arr sometimes emits >3 fractional digits or no timezone
        var trimmed = s
        if let dot = trimmed.firstIndex(of: ".") {
            let tail = trimmed[dot...]
            let tz = tail.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
            let frac = trimmed[trimmed.index(after: dot)..<(tz ?? trimmed.endIndex)]
            let tzPart = tz.map { String(trimmed[$0...]) } ?? "Z"
            trimmed = String(trimmed[..<dot]) + "." + String(frac.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) + tzPart
            if let d = try? Date(trimmed, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        } else if !s.hasSuffix("Z"), !s.contains("+"), s.count == 19 {
            return try? Date(s + "Z", strategy: Date.ISO8601FormatStyle())
        }
        return nil
    }
}

import Foundation

/// Minimal reader for Java Object Serialization streams (as produced by Android's
/// ObjectOutputStream). Supports what nzb360 backups contain: HashMap, ArrayList,
/// HashSet, boxed primitives, Strings, enums, arrays and plain serializable objects.
/// Output is mapped to `JSONValue`.
public struct JavaDeserializer {
    enum TC: UInt8 {
        case null = 0x70, reference, classDesc, object, string, array, `class`, blockData, endBlockData,
             reset, blockDataLong, exception, longString, proxyClassDesc, `enum`
    }

    public enum Failure: Error, CustomStringConvertible {
        case badMagic, eof, unsupported(UInt8, Int), badHandle(Int)
        public var description: String {
            switch self {
            case .badMagic: "Not a Java serialization stream"
            case .eof: "Unexpected end of data"
            case .unsupported(let b, let o): String(format: "Unsupported type code 0x%02X at %d", b, o)
            case .badHandle(let h): "Invalid back-reference \(h)"
            }
        }
    }

    final class ClassDesc {
        var name: String = ""
        var flags: UInt8 = 0
        var fields: [(type: Character, name: String)] = []
        var superDesc: ClassDesc?
        var isEnum: Bool { flags & 0x10 != 0 }
    }

    /// Value held in the handle table.
    enum Handle {
        case value(JSONValue)
        case desc(ClassDesc)
        case pending
    }

    private let data: [UInt8]
    private var pos = 0
    private var handles: [Handle] = []
    private static let baseHandle = 0x7E0000

    public init(data: Data) { self.data = [UInt8](data) }

    /// Read every top-level object in the stream.
    public static func parse(_ data: Data) throws -> [JSONValue] {
        var r = JavaDeserializer(data: data)
        guard try r.u16() == 0xACED else { throw Failure.badMagic }
        _ = try r.u16()
        var out: [JSONValue] = []
        while r.pos < r.data.count {
            if let v = try r.readContent() { out.append(v) }
        }
        return out
    }

    // MARK: Primitives

    private mutating func u8() throws -> UInt8 {
        guard pos < data.count else { throw Failure.eof }
        defer { pos += 1 }
        return data[pos]
    }
    private mutating func bytes(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, pos + n <= data.count else { throw Failure.eof }
        defer { pos += n }
        return data[pos..<(pos + n)]
    }
    private mutating func u16() throws -> UInt16 { let b = try bytes(2); return UInt16(b[b.startIndex]) << 8 | UInt16(b[b.startIndex + 1]) }
    private mutating func i32() throws -> Int32 {
        let b = try bytes(4)
        return b.reduce(Int32(0)) { ($0 << 8) | Int32($1) }
    }
    private mutating func i64() throws -> Int64 {
        let b = try bytes(8)
        return b.reduce(Int64(0)) { ($0 << 8) | Int64($1) }
    }
    private mutating func utf(_ len: Int) throws -> String {
        let b = try bytes(len)
        // Java "modified UTF-8": decoding as UTF-8 is correct for everything but embedded NULs/surrogates.
        return String(decoding: b, as: UTF8.self)
    }

    private mutating func newHandle(_ h: Handle) -> Int { handles.append(h); return handles.count - 1 }

    // MARK: Grammar

    private mutating func readContent() throws -> JSONValue? {
        let tc = try u8()
        switch TC(rawValue: tc) {
        case .blockData: _ = try bytes(Int(try u8())); return nil
        case .blockDataLong: _ = try bytes(Int(try i32())); return nil
        case .reset: handles.removeAll(); return nil
        default:
            pos -= 1
            return try readObject()
        }
    }

    private mutating func readObject() throws -> JSONValue {
        let start = pos
        let tc = try u8()
        switch TC(rawValue: tc) {
        case .null: return .null
        case .reference:
            let h = Int(try i32()) - Self.baseHandle
            guard handles.indices.contains(h) else { throw Failure.badHandle(h) }
            if case .value(let v) = handles[h] { return v }
            return .null
        case .string:
            let s = try utf(Int(try u16()))
            _ = newHandle(.value(.string(s)))
            return .string(s)
        case .longString:
            let s = try utf(Int(try i64()))
            _ = newHandle(.value(.string(s)))
            return .string(s)
        case .object: return try readNewObject()
        case .array: return try readArray()
        case .enum:
            _ = try readClassDesc()
            let h = newHandle(.pending)
            let name = try readObject()
            handles[h] = .value(name)
            return name
        case .class:
            let d = try readClassDesc()
            let v = JSONValue.string(d?.name ?? "")
            _ = newHandle(.value(v))
            return v
        case .classDesc, .proxyClassDesc:
            pos -= 1
            _ = try readClassDesc()
            return .null
        default:
            throw Failure.unsupported(tc, start)
        }
    }

    private mutating func readClassDesc() throws -> ClassDesc? {
        let tc = try u8()
        switch TC(rawValue: tc) {
        case .null: return nil
        case .reference:
            let h = Int(try i32()) - Self.baseHandle
            guard handles.indices.contains(h), case .desc(let d) = handles[h] else { throw Failure.badHandle(h) }
            return d
        case .classDesc:
            let d = ClassDesc()
            d.name = try utf(Int(try u16()))
            _ = try bytes(8) // serialVersionUID
            _ = newHandle(.desc(d))
            d.flags = try u8()
            let count = Int(try u16())
            for _ in 0..<count {
                let type = Character(UnicodeScalar(try u8()))
                let name = try utf(Int(try u16()))
                if type == "L" || type == "[" { _ = try readObject() } // field class name
                d.fields.append((type, name))
            }
            try skipAnnotation()
            d.superDesc = try readClassDesc()
            return d
        case .proxyClassDesc:
            let d = ClassDesc()
            _ = newHandle(.desc(d))
            let n = Int(try i32())
            for _ in 0..<n { _ = try utf(Int(try u16())) }
            try skipAnnotation()
            d.superDesc = try readClassDesc()
            return d
        default:
            throw Failure.unsupported(tc, pos - 1)
        }
    }

    /// Reads annotation contents up to TC_ENDBLOCKDATA, returning the objects found.
    @discardableResult
    private mutating func skipAnnotation() throws -> [JSONValue] {
        var objects: [JSONValue] = []
        while true {
            let tc = try u8()
            switch TC(rawValue: tc) {
            case .endBlockData: return objects
            case .blockData: _ = try bytes(Int(try u8()))
            case .blockDataLong: _ = try bytes(Int(try i32()))
            default:
                pos -= 1
                objects.append(try readObject())
            }
        }
    }

    private mutating func readPrimitive(_ t: Character) throws -> JSONValue {
        switch t {
        case "B": return .number(Double(Int8(bitPattern: try u8())))
        case "C": return .string(String(UnicodeScalar(try u16()).map(Character.init) ?? " "))
        case "D": return .number(Double(bitPattern: UInt64(bitPattern: try i64())))
        case "F": return .number(Double(Float(bitPattern: UInt32(bitPattern: try i32()))))
        case "I": return .number(Double(try i32()))
        case "J": return .number(Double(try i64()))
        case "S": return .number(Double(Int16(bitPattern: try u16())))
        case "Z": return .bool(try u8() != 0)
        default: return try readObject()
        }
    }

    private mutating func readNewObject() throws -> JSONValue {
        guard let desc = try readClassDesc() else { return .null }
        let h = newHandle(.pending)
        // Class hierarchy from the top-most superclass down.
        var chain: [ClassDesc] = []
        var c: ClassDesc? = desc
        while let cur = c { chain.insert(cur, at: 0); c = cur.superDesc }

        var fields: [String: JSONValue] = [:]
        var annotations: [JSONValue] = []
        for cd in chain {
            if cd.flags & 0x04 != 0 { // externalizable
                if cd.flags & 0x08 != 0 { annotations += try skipAnnotation() }
                continue
            }
            if cd.flags & 0x02 != 0 {
                for f in cd.fields { fields[f.name] = try readPrimitive(f.type) }
                if cd.flags & 0x01 != 0 { annotations += try skipAnnotation() }
            }
        }

        let result: JSONValue
        switch desc.name {
        case "java.lang.Boolean", "java.lang.Integer", "java.lang.Long", "java.lang.Float", "java.lang.Double",
             "java.lang.Short", "java.lang.Byte", "java.lang.Character":
            result = fields["value"] ?? .null
        case "java.util.HashMap", "java.util.LinkedHashMap", "java.util.TreeMap", "java.util.Hashtable":
            var dict: [String: JSONValue] = [:]
            var i = 0
            while i + 1 < annotations.count {
                dict[annotations[i].stringValue ?? "\(i)"] = annotations[i + 1]
                i += 2
            }
            result = .object(dict)
        case "java.util.ArrayList", "java.util.LinkedList", "java.util.HashSet", "java.util.LinkedHashSet", "java.util.TreeSet", "java.util.ArrayDeque":
            result = .array(annotations)
        default:
            var obj = fields
            obj["__class"] = .string(desc.name)
            result = .object(obj)
        }
        handles[h] = .value(result)
        return result
    }

    private mutating func readArray() throws -> JSONValue {
        let desc = try readClassDesc()
        let h = newHandle(.pending)
        let n = Int(try i32())
        let elementType: Character = {
            guard let name = desc?.name, name.count >= 2 else { return "L" }
            return name[name.index(after: name.startIndex)]
        }()
        if elementType == "B" { // byte[]: keep as base64 string
            let b = try bytes(n)
            let v = JSONValue.string(Data(b).base64EncodedString())
            handles[h] = .value(v)
            return v
        }
        var items: [JSONValue] = []
        items.reserveCapacity(n)
        for _ in 0..<n { items.append(try readPrimitive(elementType == "[" ? "L" : elementType)) }
        handles[h] = .value(.array(items))
        return .array(items)
    }
}

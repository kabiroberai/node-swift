internal import CNodeAPI

public enum NodeTypedArrayKind {
    struct UnknownKindError: Error {
        let kind: napi_typedarray_type
    }

    case int8
    case uint8
    case uint8Clamped
    case int16
    case uint16
    case int32
    case uint32
    case float32
    case float64
    case int64
    case uint64

    init(raw: napi_typedarray_type) throws {
        switch raw {
        case napi_int8_array:
            self = .int8
        case napi_uint8_array:
            self = .uint8
        case napi_uint8_clamped_array:
            self = .uint8Clamped
        case napi_int16_array:
            self = .int16
        case napi_uint16_array:
            self = .uint16
        case napi_int32_array:
            self = .int32
        case napi_uint32_array:
            self = .uint32
        case napi_float32_array:
            self = .float32
        case napi_float64_array:
            self = .float64
        case napi_bigint64_array:
            self = .int64
        case napi_biguint64_array:
            self = .uint64
        default:
            throw UnknownKindError(kind: raw)
        }
    }

    var raw: napi_typedarray_type {
        switch self {
        case .int8:
            return napi_int8_array
        case .uint8:
            return napi_uint8_array
        case .uint8Clamped:
            return napi_uint8_clamped_array
        case .int16:
            return napi_int16_array
        case .uint16:
            return napi_uint16_array
        case .int32:
            return napi_int32_array
        case .uint32:
            return napi_uint32_array
        case .float32:
            return napi_float32_array
        case .float64:
            return napi_float64_array
        case .int64:
            return napi_bigint64_array
        case .uint64:
            return napi_biguint64_array
        }
    }
}

public protocol NodeTypedArrayElement {
    @_spi(NodeAPI) static var kind: NodeTypedArrayKind { get }
}

extension NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind {
        fatalError("Custom implementations of NodeTypedArrayKind are unsupported")
    }
}

extension Int8: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .int8 }
}

extension UInt8: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .uint8 }
}

extension Int16: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .int16 }
}

extension UInt16: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .uint16 }
}

extension Int32: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .int32 }
}

extension UInt32: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .uint32 }
}

extension Float: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .float32 }
}

extension Double: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .float64 }
}

extension Int64: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .int64 }
}

extension UInt64: NodeTypedArrayElement {
    @_spi(NodeAPI) public static var kind: NodeTypedArrayKind { .uint64 }
}

public class NodeAnyTypedArray: NodeObject {

    fileprivate static func isObjectType(for value: NodeValueBase, kind: NodeTypedArrayKind?) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_typedarray(env.raw, value.rawValue(), &result))
        guard result else { return false }
        if let kind = kind {
            var type = napi_int8_array
            try env.check(napi_get_typedarray_info(env.raw, value.rawValue(), &type, nil, nil, nil, nil))
            guard type == kind.raw else { return false }
        }
        return true
    }

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        try isObjectType(for: value, kind: nil)
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init(for buf: NodeArrayBuffer, kind: NodeTypedArrayKind, offset: Int = 0, count: Int) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_create_typedarray(env.raw, kind.raw, count, buf.base.rawValue(), offset, &result))
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public final func kind() throws -> NodeTypedArrayKind {
        let env = base.environment
        var type = napi_int8_array
        try env.check(napi_get_typedarray_info(env.raw, base.rawValue(), &type, nil, nil, nil, nil))
        return try NodeTypedArrayKind(raw: type)
    }

    // offset in backing array buffer
    public final func byteOffset() throws -> Int {
        let env = base.environment
        var offset = 0
        try env.check(napi_get_typedarray_info(env.raw, base.rawValue(), nil, nil, nil, nil, &offset))
        return offset
    }

    public final func withUnsafeMutableRawBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) throws -> T {
        let env = base.environment
        var data: UnsafeMutableRawPointer?
        var count = 0
        try env.check(napi_get_typedarray_info(env.raw, base.rawValue(), nil, &count, &data, nil, nil))
        // TODO: Do we need to advance `data` by `offset`/a multiple of offset?
        return try body(UnsafeMutableRawBufferPointer(start: data, count: count))
    }

}

public class NodeTypedArray<Element: NodeTypedArrayElement>: NodeAnyTypedArray {

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        try isObjectType(for: value, kind: Element.kind)
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init(for buf: NodeArrayBuffer, offset: Int = 0, count: Int) throws {
        try super.init(for: buf, kind: Element.kind, offset: offset, count: count)
    }

    public func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableBufferPointer<Element>) throws -> T) throws -> T {
        try withUnsafeMutableRawBytes { try body($0.bindMemory(to: Element.self)) }
    }

}

public final class NodeUInt8ClampedArray: NodeAnyTypedArray {

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        try isObjectType(for: value, kind: .uint8Clamped)
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init(for buf: NodeArrayBuffer, offset: Int = 0, count: Int) throws {
        try super.init(for: buf, kind: .uint8Clamped, offset: offset, count: count)
    }

    public func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableBufferPointer<UInt8>) throws -> T) throws -> T {
        try withUnsafeMutableRawBytes { try body($0.bindMemory(to: UInt8.self)) }
    }

}

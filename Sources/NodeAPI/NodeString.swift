import CNodeAPI

public final class NodeString: NodePrimitive, NodeName, NodeValueCoercible {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(coercing value: NodeValueConvertible) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(
            napi_coerce_to_string(env.raw, value.rawValue(), &coerced)
        )
        self.base = NodeValueBase(raw: coerced, in: ctx)
    }

    public init(_ string: String) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        var string = string
        try string.withUTF8 { buf in
            try buf.withMemoryRebound(to: Int8.self) { newBuf in
                try env.check(
                    napi_create_string_utf8(env.raw, newBuf.baseAddress, newBuf.count, &result)
                )
            }
        }
        self.base = NodeValueBase(raw: result, in: ctx)
    }

    public func string() throws -> String {
        let env = base.environment
        let nodeVal = try base.rawValue()
        var length: Int = 0
        try env.check(napi_get_value_string_utf8(env.raw, nodeVal, nil, 0, &length))
        // napi nul-terminates strings
        let totLength = length + 1
        return try String(portableUnsafeUninitializedCapacity: totLength) {
            try $0.withMemoryRebound(to: CChar.self) {
                try env.check(napi_get_value_string_utf8(env.raw, nodeVal, $0.baseAddress!, totLength, &length))
                return length
            }
        }!
    }

}

extension String: NodePrimitiveConvertible, NodeName, NodeValueCreatable {
    public func nodeValue() throws -> NodeValue {
        try NodeString(self)
    }

    public init(_ value: NodeString) throws {
        self = try value.string()
    }
}

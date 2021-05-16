import CNodeAPI

public final class NodeString: NodeValue, NodeName, NodeValueCoercible {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(coercing value: NodeValueConvertible, in ctx: NodeContext) throws {
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(
            napi_coerce_to_string(env.raw, value.rawValue(in: ctx), &coerced)
        )
        self.base = NodeValueBase(raw: coerced, in: ctx)
    }

    public init(_ string: String, in ctx: NodeContext) throws {
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
        let buf = malloc(totLength).bindMemory(to: Int8.self, capacity: totLength)
        try env.check(napi_get_value_string_utf8(env.raw, nodeVal, buf, totLength, &length))
        return String(bytesNoCopy: buf, length: length, encoding: .utf8, freeWhenDone: true)!
    }

}

extension String: NodeValueConvertible, NodeName {
    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        try NodeString(self, in: ctx)
    }
}

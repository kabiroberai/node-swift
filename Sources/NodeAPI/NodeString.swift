import CNodeAPI

public final class NodeString: NodeValueStorage, NodeName {

    public var storedValue: NodeValue
    public init(_ value: NodeValue) {
        self.storedValue = value
    }

    public init(coercing value: NodeValueConvertible, in ctx: NodeContext) throws {
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(
            napi_coerce_to_string(env.raw, value.nodeValue(in: ctx).rawValue(), &coerced)
        )
        self.storedValue = NodeValue(raw: coerced, in: ctx)
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
        self.storedValue = NodeValue(raw: result, in: ctx)
    }

    public func value() throws -> String {
        let env = storedValue.environment
        let nodeVal = try storedValue.rawValue()
        var length: Int = 0
        try env.check(napi_get_value_string_utf8(env.raw, nodeVal, nil, 0, &length))
        // napi nul-terminates strings
        let totLength = length + 1
        let buf = malloc(totLength).bindMemory(to: Int8.self, capacity: totLength)
        try env.check(napi_get_value_string_utf8(env.raw, nodeVal, buf, totLength, &length))
        return String(bytesNoCopy: buf, length: length, encoding: .utf8, freeWhenDone: true)!
    }

}

extension String: NodeValueLiteral, NodeName, NodeValueConvertible {
    func storage(in ctx: NodeContext) throws -> NodeString {
        try NodeString(self, in: ctx)
    }
}

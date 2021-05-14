import CNAPI

public final class NodeString: NodeValueStorage {

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in env: NodeEnvironment) throws {
        let nodeValue = try value.nodeValue(in: env)
        guard try nodeValue.type(in: env) == .string else {
            throw NodeError(.stringExpected)
        }
        self.storedValue = nodeValue
    }

    public init(coercing value: NodeValueConvertible, in env: NodeEnvironment) throws {
        var coerced: napi_value!
        try env.check(napi_coerce_to_string(env.raw, value.nodeValue(in: env).rawValue(in: env), &coerced))
        self.storedValue = NodeValue(raw: coerced, in: env)
    }

    public init(_ string: String, in env: NodeEnvironment) throws {
        var result: napi_value!
        var string = string
        try string.withUTF8 { buf in
            try buf.withMemoryRebound(to: Int8.self) { newBuf in
                try env.check(napi_create_string_utf8(env.raw, newBuf.baseAddress, newBuf.count, &result))
            }
        }
        self.storedValue = NodeValue(raw: result, in: env)
    }

    public func value(in env: NodeEnvironment) throws -> String {
        let nodeVal = try storedValue.rawValue(in: env)
        var length: Int = 0
        try env.check(napi_get_value_string_utf8(env.raw, nodeVal, nil, 0, &length))
        // napi nul-terminates strings
        let totLength = length + 1
        let buf = malloc(totLength).bindMemory(to: Int8.self, capacity: totLength)
        try env.check(napi_get_value_string_utf8(env.raw, nodeVal, buf, totLength, &length))
        return String(bytesNoCopy: buf, length: length, encoding: .utf8, freeWhenDone: true)!
    }

}

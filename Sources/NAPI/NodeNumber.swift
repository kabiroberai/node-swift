import CNAPI

public final class NodeNumber: NodeValueStorage {

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in env: NodeEnvironment) throws {
        let nodeValue = try value.nodeValue(in: env)
        guard try nodeValue.type(in: env) == .number else {
            throw NodeError(.numberExpected)
        }
        self.storedValue = nodeValue
    }

    public init(coercing value: NodeValueConvertible, in env: NodeEnvironment) throws {
        var coerced: napi_value!
        try env.check(napi_coerce_to_number(env.raw, value.nodeValue(in: env).rawValue(in: env), &coerced))
        self.storedValue = NodeValue(raw: coerced, in: env)
    }

    public init(double: Double, in env: NodeEnvironment) throws {
        var result: napi_value!
        try env.check(napi_create_double(env.raw, double, &result))
        self.storedValue = NodeValue(raw: result, in: env)
    }

    public init(integer: Int64, in env: NodeEnvironment) throws {
        var result: napi_value!
        try env.check(napi_create_int64(env.raw, integer, &result))
        self.storedValue = NodeValue(raw: result, in: env)
    }

    public func double(in env: NodeEnvironment) throws -> Double {
        var value: Double = 0
        try env.check(napi_get_value_double(env.raw, storedValue.rawValue(in: env), &value))
        return value
    }

    public func int32(in env: NodeEnvironment) throws -> Int32 {
        var value: Int32 = 0
        try env.check(napi_get_value_int32(env.raw, storedValue.rawValue(in: env), &value))
        return value
    }

    public func int64(in env: NodeEnvironment) throws -> Int64 {
        var value: Int64 = 0
        try env.check(napi_get_value_int64(env.raw, storedValue.rawValue(in: env), &value))
        return value
    }

}

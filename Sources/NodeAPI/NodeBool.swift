import CNodeAPI

public final class NodeBool: NodeValueStorage {

    public var storedValue: NodeValue

    public init(value: Bool, in env: NodeEnvironment) throws {
        var val: napi_value!
        try env.check(napi_get_boolean(env.raw, value, &val))
        storedValue = NodeValue(raw: val, in: env)
    }

    public init(_ value: NodeValueConvertible, in env: NodeEnvironment) throws {
        let nodeValue = try value.nodeValue(in: env)
        guard try nodeValue.type(in: env) == .boolean else {
            throw NodeError(.booleanExpected)
        }
        self.storedValue = nodeValue
    }

    public init(coercing value: NodeValueConvertible, in env: NodeEnvironment) throws {
        var coerced: napi_value!
        try env.check(napi_coerce_to_bool(env.raw, value.nodeValue(in: env).rawValue(in: env), &coerced))
        self.storedValue = NodeValue(raw: coerced, in: env)
    }

    public func value(in env: NodeEnvironment) throws -> Bool {
        var value = false
        try env.check(napi_get_value_bool(env.raw, storedValue.rawValue(in: env), &value))
        return value
    }

}

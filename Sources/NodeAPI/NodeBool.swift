import CNodeAPI

public final class NodeBool: NodeValueStorage {

    public var storedValue: NodeValue
    public init(_ value: NodeValue) {
        self.storedValue = value
    }

    public init(coercing value: NodeValueConvertible, in ctx: NodeContext) throws {
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(napi_coerce_to_bool(env.raw, value.nodeValue(in: ctx).rawValue(), &coerced))
        self.storedValue = NodeValue(raw: coerced, in: ctx)
    }

    public init(_ bool: Bool, in ctx: NodeContext) throws {
        let env = ctx.environment
        var val: napi_value!
        try env.check(napi_get_boolean(env.raw, bool, &val))
        storedValue = NodeValue(raw: val, in: ctx)
    }

    public func value() throws -> Bool {
        let env = storedValue.environment
        var value = false
        try env.check(napi_get_value_bool(env.raw, storedValue.rawValue(), &value))
        return value
    }

}

extension Bool: NodeValueLiteral {
    func storage(in ctx: NodeContext) throws -> NodeBool {
        try NodeBool(self, in: ctx)
    }
}

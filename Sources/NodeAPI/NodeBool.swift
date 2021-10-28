@_implementationOnly import CNodeAPI

public final class NodeBool: NodePrimitive, NodeValueCoercible {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(coercing value: NodeValueConvertible) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(napi_coerce_to_bool(env.raw, value.rawValue(), &coerced))
        self.base = NodeValueBase(raw: coerced, in: ctx)
    }

    public init(_ bool: Bool) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var val: napi_value!
        try env.check(napi_get_boolean(env.raw, bool, &val))
        base = NodeValueBase(raw: val, in: ctx)
    }

    public func bool() throws -> Bool {
        let env = base.environment
        var value = false
        try env.check(napi_get_value_bool(env.raw, base.rawValue(), &value))
        return value
    }

}

extension Bool: NodePrimitiveConvertible, NodeValueCreatable {
    public func nodeValue() throws -> NodeValue {
        try NodeBool(self)
    }

    public static func from(_ value: NodeBool) throws -> Bool {
        try value.bool()
    }
}

import CNodeAPI

public final class NodeNumber: NodeValueStorage {

    public var storedValue: NodeValue
    public init(_ value: NodeValue) {
        self.storedValue = value
    }

    public init(coercing value: NodeValueConvertible, in ctx: NodeContext) throws {
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(napi_coerce_to_number(env.raw, value.nodeValue(in: ctx).rawValue(), &coerced))
        self.storedValue = NodeValue(raw: coerced, in: ctx)
    }

    public init(_ double: Double, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_create_double(env.raw, double, &result))
        self.storedValue = NodeValue(raw: result, in: ctx)
    }

    public init(_ integer: Int64, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_create_int64(env.raw, integer, &result))
        self.storedValue = NodeValue(raw: result, in: ctx)
    }

    public func double() throws -> Double {
        let env = storedValue.environment
        var value: Double = 0
        try env.check(napi_get_value_double(env.raw, storedValue.rawValue(), &value))
        return value
    }

    public func int32() throws -> Int32 {
        let env = storedValue.environment
        var value: Int32 = 0
        try env.check(napi_get_value_int32(env.raw, storedValue.rawValue(), &value))
        return value
    }

    public func int64() throws -> Int64 {
        let env = storedValue.environment
        var value: Int64 = 0
        try env.check(napi_get_value_int64(env.raw, storedValue.rawValue(), &value))
        return value
    }

}

extension Int64: NodeValueLiteral {
    func storage(in ctx: NodeContext) throws -> NodeNumber {
        try NodeNumber(self, in: ctx)
    }
}

extension Double: NodeValueLiteral {
    func storage(in ctx: NodeContext) throws -> NodeNumber {
        try NodeNumber(self, in: ctx)
    }
}

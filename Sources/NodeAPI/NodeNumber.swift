@_implementationOnly import CNodeAPI

public final class NodeNumber: NodePrimitive, NodeValueCoercible {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(coercing value: NodeValueConvertible) throws {
        let val = try value.nodeValue()
        if let val = val as? NodeNumber {
            self.base = val.base
            return
        }
        let ctx = NodeContext.current
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(napi_coerce_to_number(env.raw, val.rawValue(), &coerced))
        self.base = NodeValueBase(raw: coerced, in: ctx)
    }

    public init(_ double: Double) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_create_double(env.raw, double, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }

    public func double() throws -> Double {
        let env = base.environment
        var value: Double = 0
        try env.check(napi_get_value_double(env.raw, base.rawValue(), &value))
        return value
    }

}

extension Double: NodePrimitiveConvertible, NodeValueCreatable {
    public func nodeValue() throws -> NodeValue {
        try NodeNumber(self)
    }

    public static func from(_ value: NodeNumber) throws -> Double {
        try value.double()
    }
}

extension Int: NodePrimitiveConvertible, AnyNodeValueCreatable {
    public func nodeValue() throws -> NodeValue {
        try Double(self).nodeValue()
    }

    public static func from(_ value: NodeValue) throws -> Int? {
        try value.as(Double.self).flatMap(Int.init(exactly:))
    }
}

@_implementationOnly import CNodeAPI

public final class NodeNull: NodePrimitive {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init() throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_get_null(env.raw, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }

}

extension Optional: NodeValueConvertible, NodePropertyConvertible where Wrapped: NodeValueConvertible {
    public func nodeValue() throws -> NodeValue {
        try self?.nodeValue() ?? NodeNull()
    }
}

extension Optional: AnyNodeValueCreatable where Wrapped: AnyNodeValueCreatable {
    public static func from(_ value: NodeValue) throws -> Wrapped?? {
        switch try value.nodeType() {
        case .null, .undefined:
            // conversion succeeded, and we got nil
            return Wrapped??.some(.none)
        default:
            if let val = try Wrapped.from(value) {
                return val
            } else {
                // conversion failed
                return Wrapped??.none
            }
        }
    }
}

extension Optional: NodeClassPropertyConvertible where Wrapped: NodePrimitiveConvertible {}

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

    // we don't conform to NodeValueCreatable because the associatedtype
    // would have to be NodeNull i.e. we'd never get a .some optional
}

extension Optional: NodeClassPropertyConvertible where Wrapped: NodePrimitiveConvertible {}

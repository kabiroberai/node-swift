internal import CNodeAPI

public final class NodeSymbol: NodePrimitive, NodeName {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(description: String? = nil) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        let descRaw = try description.map { try $0.rawValue() }
        try env.check(napi_create_symbol(env.raw, descRaw, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }

}

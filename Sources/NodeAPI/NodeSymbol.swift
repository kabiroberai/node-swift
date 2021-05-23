import CNodeAPI

public final class NodeSymbol: NodeValue, NodeName {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(description: String? = nil, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        let descRaw = try description.map {
            try NodeString($0, in: ctx).base.rawValue()
        }
        try env.check(napi_create_symbol(env.raw, descRaw, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }

}

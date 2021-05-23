import CNodeAPI

public final class NodeNull: NodeValue {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_get_null(env.raw, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }

}

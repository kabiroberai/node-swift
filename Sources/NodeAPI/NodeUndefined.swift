import CNodeAPI

public final class NodeUndefined: NodePrimitive {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init() throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_get_undefined(env.raw, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }

}

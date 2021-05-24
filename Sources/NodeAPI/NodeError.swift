import CNodeAPI

public final class NodeError: NodeObject, NodeExceptionConvertible {

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_error(env.raw, value.rawValue(), &result))
        return result
    }

    public var exception: NodeValue { self }

    public init(nodeErrorCode code: String, message: String, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        try env.check(
            napi_create_error(
                env.raw,
                code.rawValue(in: ctx),
                message.rawValue(in: ctx),
                &result
            )
        )
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public init(typeErrorCode code: String, message: String, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        try env.check(
            napi_create_type_error(
                env.raw,
                code.rawValue(in: ctx),
                message.rawValue(in: ctx),
                &result
            )
        )
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public init(rangeErrorCode code: String, message: String, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        try env.check(
            napi_create_range_error(
                env.raw,
                code.rawValue(in: ctx),
                message.rawValue(in: ctx),
                &result
            )
        )
        super.init(NodeValueBase(raw: result, in: ctx))
    }

}

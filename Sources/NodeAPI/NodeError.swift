import CNodeAPI

public final class NodeError: NodeValue, Error {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

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
        base = NodeValueBase(raw: result, in: ctx)
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
        base = NodeValueBase(raw: result, in: ctx)
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
        base = NodeValueBase(raw: result, in: ctx)
    }

}

public func nodeFatalError(_ message: String = "", file: StaticString = #file, line: UInt = #line) -> Never {
    var message = message
    message.withUTF8 {
        $0.withMemoryRebound(to: CChar.self) { messageBuf -> Never in
            var loc = "\(file):\(line)"
            loc.withUTF8 {
                $0.withMemoryRebound(to: CChar.self) { locBuf in
                    napi_fatal_error(locBuf.baseAddress, locBuf.count, messageBuf.baseAddress, messageBuf.count)
                }
            }
        }
    }
}

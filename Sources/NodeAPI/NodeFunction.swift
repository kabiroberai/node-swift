import CNodeAPI

private class CallbackWrapper {
    let callback: NodeFunction.Callback
    init(_ callback: @escaping NodeFunction.Callback) {
        self.callback = callback
    }
}

private func cCallback(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        var argc: Int = 0
        try ctx.environment.check(napi_get_cb_info(ctx.environment.raw, info, &argc, nil, nil, nil))
        var this: napi_value!
        var data: UnsafeMutableRawPointer!
        let args = try [napi_value?](unsafeUninitializedCapacity: argc) { buf, len in
            len = 0
            try ctx.environment.check(napi_get_cb_info(ctx.environment.raw, info, &argc, buf.baseAddress, &this, &data))
            len = argc
        }.map { NodeValueBase(raw: $0!, in: ctx).as(AnyNodeValue.self) }
        let callback = Unmanaged<CallbackWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callback.callback(
            ctx,
            NodeValueBase(raw: this, in: ctx).as(AnyNodeValue.self),
            args
        ).rawValue(in: ctx)
    }
}

public final class NodeFunction: NodeValue {

    public typealias Callback = (_ ctx: NodeContext, _ this: NodeValue, _ args: [NodeValue]) throws -> NodeValueConvertible

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(name: String = "", in ctx: NodeContext, callback: @escaping Callback) throws {
        let env = ctx.environment
        let wrapper = CallbackWrapper(callback)
        let data = Unmanaged.passRetained(wrapper)
        var name = name
        var value: napi_value!
        try name.withUTF8 {
            try $0.withMemoryRebound(to: CChar.self) {
                try env.check(
                    napi_create_function(
                        env.raw,
                        $0.baseAddress, $0.count,
                        cCallback,
                        data.toOpaque(),
                        &value
                    )
                )
            }
        }
        self.base = NodeValueBase(raw: value, in: ctx)
        try addFinalizer { _ in data.release() }
    }

    public func call(
        in ctx: NodeContext,
        receiver: NodeValueConvertible,
        args: [NodeValueConvertible]
    ) throws -> NodeValue {
        let env = ctx.environment
        var ret: napi_value!
        let rawArgs = try args.map { arg -> napi_value? in
            try arg.rawValue(in: ctx)
        }
        try env.check(
            napi_call_function(
                env.raw,
                receiver.rawValue(in: ctx),
                base.rawValue(),
                rawArgs.count, rawArgs,
                &ret
            )
        )
        return NodeValueBase(raw: ret, in: ctx).as(AnyNodeValue.self)
    }

    @discardableResult
    public func callAsFunction(in ctx: NodeContext, _ args: NodeValueConvertible...) throws -> NodeValue {
        try call(in: ctx, receiver: ctx.undefined(), args: args)
    }

}

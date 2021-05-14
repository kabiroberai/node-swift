import CNodeAPI

private class CallbackWrapper {
    let callback: NodeFunction.Callback
    init(_ callback: @escaping NodeFunction.Callback) {
        self.callback = callback
    }
}

private func cCallback(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    try? NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        var argc: Int = 0
        try ctx.environment.check(napi_get_cb_info(ctx.environment.raw, info, &argc, nil, nil, nil))
        var this: napi_value!
        var data: UnsafeMutableRawPointer!
        let args = try [napi_value?](unsafeUninitializedCapacity: argc) { buf, len in
            len = 0
            try ctx.environment.check(napi_get_cb_info(ctx.environment.raw, info, &argc, buf.baseAddress, &this, &data))
            len = argc
        }.map { NodeValue(raw: $0!, in: ctx) }
        let callback = Unmanaged<CallbackWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callback.callback(ctx, NodeValue(raw: this, in: ctx), args).nodeValue(in: ctx).rawValue()
    }
}

public final class NodeFunction: NodeValueStorage {

    public typealias Callback = (_ ctx: NodeContext, _ this: NodeValue, _ args: [NodeValue]) throws -> NodeValueConvertible

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in ctx: NodeContext) throws {
        self.storedValue = try value.nodeValue(in: ctx)
    }

    public init(in ctx: NodeContext, name: String, callback: @escaping Callback) throws {
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
        let nodeValue = NodeValue(raw: value, in: ctx)
        try nodeValue.addFinalizer { _ in data.release() }
        self.storedValue = nodeValue
    }

    public func call(
        withContext ctx: NodeContext,
        receiver: NodeValueConvertible,
        args: [NodeValueConvertible]
    ) throws -> NodeValue {
        let env = ctx.environment
        var ret: napi_value!
        let rawArgs = try args.map { arg -> napi_value? in
            try arg.nodeValue(in: ctx).rawValue()
        }
        try env.check(
            napi_call_function(
                env.raw,
                receiver.nodeValue(in: ctx).rawValue(),
                storedValue.rawValue(),
                rawArgs.count, rawArgs,
                &ret
            )
        )
        return NodeValue(raw: ret, in: ctx)
    }

    @discardableResult
    public func callAsFunction(withContext ctx: NodeContext, _ args: NodeValueConvertible...) throws -> NodeValue {
        try call(withContext: ctx, receiver: ctx.undefined(), args: args)
    }

}

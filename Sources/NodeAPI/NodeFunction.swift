import CNodeAPI

private typealias CallbackWrapper = Box<NodeFunction.Callback>

private func cCallback(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeFunction.CallbackInfo(raw: info, in: ctx)
        let data = arguments.data
        let callback = Unmanaged<CallbackWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callback.value(ctx, arguments).rawValue(in: ctx)
    }
}

public final class NodeFunction: NodeValue {

    public struct CallbackInfo {
        public let this: NodeValue
        public let target: NodeFunction? // new.target
        public let arguments: [NodeValue]
        let data: UnsafeMutableRawPointer

        init(raw: napi_callback_info, in ctx: NodeContext) throws {
            let env = ctx.environment

            var argc: Int = 0
            try env.check(napi_get_cb_info(env.raw, raw, &argc, nil, nil, nil))
            var this: napi_value!
            var data: UnsafeMutableRawPointer!
            let args = try [napi_value?](unsafeUninitializedCapacity: argc) { buf, len in
                len = 0
                try env.check(napi_get_cb_info(env.raw, raw, &argc, buf.baseAddress, &this, &data))
                len = argc
            }.map { NodeValueBase(raw: $0!, in: ctx).as(AnyNodeValue.self) }

            var newTarget: napi_value?
            try env.check(napi_get_new_target(env.raw, raw, &newTarget))

            self.this = NodeValueBase(raw: this, in: ctx).as(AnyNodeValue.self)
            self.target = newTarget.map { NodeValueBase(raw: $0, in: ctx).as(NodeFunction.self) }
            self.data = data
            self.arguments = args
        }
    }

    public typealias Callback = (_ ctx: NodeContext, _ info: CallbackInfo) throws -> NodeValueConvertible

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    private static let callbackKey = NodeWrappedDataKey<CallbackWrapper>()

    public init(name: String = "", in ctx: NodeContext, callback: @escaping Callback) throws {
        let env = ctx.environment
        let wrapper = CallbackWrapper(callback)
        let data = Unmanaged.passUnretained(wrapper)
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
        // we retain CallbackWrapper using the wrappedValue functionality instead of
        // using Unmanaged.passRetained for data, since napi_create_function doesn't
        // accept a finalizer
        try self.as(NodeObject.self).setWrappedValue(wrapper, forKey: Self.callbackKey)
    }

    public func call(
        in ctx: NodeContext,
        receiver: NodeValueConvertible,
        arguments: [NodeValueConvertible]
    ) throws -> NodeValue {
        let env = ctx.environment
        var ret: napi_value!
        let rawArgs = try arguments.map { arg -> napi_value? in
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
        try call(in: ctx, receiver: ctx.undefined(), arguments: args)
    }

}

import CNodeAPI

private typealias CallbackWrapper = Box<NodeFunction.Callback>

private func cCallback(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeFunction.CallbackInfo(raw: info, in: ctx)
        let data = arguments.data
        let callback = Unmanaged<CallbackWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callback.value(arguments).rawValue()
    }
}

public final class NodeFunction: NodeObject {

    public struct CallbackInfo {
        public let this: NodeObject?
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
            }.map { try NodeValueBase(raw: $0!, in: ctx).concrete() }

            var newTarget: napi_value?
            try env.check(napi_get_new_target(env.raw, raw, &newTarget))

            self.this = try NodeValueBase(raw: this, in: ctx).as(NodeObject.self)
            self.target = try newTarget.flatMap { try NodeValueBase(raw: $0, in: ctx).as(NodeFunction.self) }
            self.data = data
            self.arguments = args
        }
    }

    public typealias Callback = (_ info: CallbackInfo) throws -> NodeValueConvertible

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    // this may seem useless since .function is handled in NodeValueType, but
    // consider the following example:
    // try NodeObject(
    //   in: ctx,
    //   constructor: ctx.global().Function.get(in: ctx)
    // ).as(NodeFunction.self)
    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        try value.type() == .function
    }

    public init(name: String = "", callback: @escaping (_ info: CallbackInfo) throws -> NodeValueConvertible) throws {
        let ctx = NodeContext.current
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
        super.init(NodeValueBase(raw: value, in: ctx))
        // we retain CallbackWrapper using the finalizer functionality instead of
        // using Unmanaged.passRetained for data, since napi_create_function doesn't
        // accept a finalizer
        try addFinalizer { _ = wrapper }
    }

    public func call(
        receiver: NodeValueConvertible,
        arguments: [NodeValueConvertible]
    ) throws -> NodeValue {
        let env = base.environment
        var ret: napi_value!
        let rawArgs = try arguments.map { arg -> napi_value? in
            try arg.rawValue()
        }
        try env.check(
            napi_call_function(
                env.raw,
                receiver.rawValue(),
                base.rawValue(),
                rawArgs.count, rawArgs,
                &ret
            )
        )
        return try NodeValueBase(raw: ret, in: .current).concrete()
    }

    @discardableResult
    public func callAsFunction(_ args: NodeValueConvertible...) throws -> NodeValue {
        try call(receiver: NodeUndefined(), arguments: args)
    }

}

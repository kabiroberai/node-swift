import CNodeAPI

private class CallbackWrapper {
    let callback: NodeFunction.Callback
    init(_ callback: @escaping NodeFunction.Callback) {
        self.callback = callback
    }
}

private func cCallback(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    try? NodeEnvironment.withRaw(rawEnv) { env -> napi_value in
        var argc: Int = 0
        try env.check(napi_get_cb_info(env.raw, info, &argc, nil, nil, nil))
        var this: napi_value!
        var data: UnsafeMutableRawPointer!
        let args = try [napi_value?](unsafeUninitializedCapacity: argc) { buf, len in
            len = 0
            try env.check(napi_get_cb_info(env.raw, info, &argc, buf.baseAddress, &this, &data))
            len = argc
        }.map { NodeValue(raw: $0!, in: env) }
        let callback = Unmanaged<CallbackWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callback.callback(env, NodeValue(raw: this, in: env), args).rawValue(in: env)
    }
}

public final class NodeFunction: NodeValueStorage {

    public typealias Callback = (_ env: NodeEnvironment, _ this: NodeValue, _ args: [NodeValue]) throws -> NodeValue

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in env: NodeEnvironment) throws {
        let nodeValue = try value.nodeValue(in: env)
        guard try nodeValue.type(in: env) == .function else {
            throw NodeError(.functionExpected)
        }
        self.storedValue = nodeValue
    }

    public init(in env: NodeEnvironment, name: String, callback: @escaping Callback) throws {
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
        let nodeValue = NodeValue(raw: value, in: env)
        try nodeValue.addFinalizer(in: env) { _ in data.release() }
        self.storedValue = nodeValue
    }

    public func call(in env: NodeEnvironment, receiver: NodeValue, args: [NodeValue]) throws -> NodeValue {
        var ret: napi_value!
        let rawArgs = try args.map { arg -> napi_value? in
            try arg.rawValue(in: env)
        }
        try env.check(
            napi_call_function(
                env.raw,
                receiver.rawValue(in: env),
                storedValue.rawValue(in: env),
                rawArgs.count, rawArgs,
                &ret
            )
        )
        return NodeValue(raw: ret, in: env)
    }

    public func callAsFunction(in env: NodeEnvironment, _ args: NodeValue...) throws -> NodeValue {
        try call(in: env, receiver: NodeValue(undefinedIn: env), args: args)
    }

}

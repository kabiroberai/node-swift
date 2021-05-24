import CNodeAPI

private typealias ConstructorWrapper = Box<NodeFunction.Callback>

private func cConstructor(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeFunction.CallbackInfo(raw: info, in: ctx)
        let data = arguments.data
        let callbacks = Unmanaged<ConstructorWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callbacks.value(ctx, arguments).rawValue(in: ctx)
    }
}

extension NodeContext {

    public func defineClass(
        name: String = "",
        constructor: @escaping NodeFunction.Callback,
        properties: [NodePropertyDescriptor]
    ) throws -> NodeFunction {
        var descriptors: [napi_property_descriptor] = []
        var callbacks: [NodePropertyDescriptor.Callbacks] = []
        for prop in properties {
            let (desc, cb) = try prop.raw(in: self)
            descriptors.append(desc)
            if let cb = cb {
                callbacks.append(cb)
            }
        }
        var name = name
        var result: napi_value!
        let ctorWrapper = ConstructorWrapper(constructor)
        try name.withUTF8 {
            try $0.withMemoryRebound(to: CChar.self) { nameUTF in
                try environment.check(
                    napi_define_class(
                        environment.raw,
                        nameUTF.baseAddress,
                        nameUTF.count,
                        cConstructor,
                        Unmanaged.passUnretained(ctorWrapper).toOpaque(),
                        descriptors.count,
                        descriptors,
                        &result
                    )
                )
            }
        }
        let ret = NodeFunction(NodeValueBase(raw: result, in: self))
        // retain ctor, callbacks
        try ret.addFinalizer { _ in
            _ = ctorWrapper
            _ = callbacks
        }
        return ret
    }

}

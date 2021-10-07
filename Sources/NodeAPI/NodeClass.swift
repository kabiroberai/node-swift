import CNodeAPI

private typealias ConstructorWrapper = Box<NodeFunction.Callback>

private func cConstructor(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeFunction.CallbackInfo(raw: info, in: ctx)
        let data = arguments.data
        let callbacks = Unmanaged<ConstructorWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callbacks.value(arguments).rawValue()
    }
}

extension NodeFunction {

    public convenience init(
        className: String = "",
        constructor: @escaping NodeFunction.Callback,
        properties: NodeClassPropertyList
    ) throws {
        var descriptors: [napi_property_descriptor] = []
        var callbacks: [NodeProperty.Callbacks] = []
        for (propName, prop) in properties.elements {
            let nodeProp = prop.nodeProperty
            let (desc, cb) = try nodeProp.raw(name: propName)
            descriptors.append(desc)
            if let cb = cb {
                callbacks.append(cb)
            }
        }
        let ctx = NodeContext.current
        let env = ctx.environment
        var name = className
        var result: napi_value!
        let ctorWrapper = ConstructorWrapper(constructor)
        try name.withUTF8 {
            try $0.withMemoryRebound(to: CChar.self) { nameUTF in
                try env.check(
                    napi_define_class(
                        env.raw,
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
        self.init(NodeValueBase(raw: result, in: ctx))
        // retain ctor, callbacks
        try addFinalizer {
            _ = ctorWrapper
            _ = callbacks
        }
    }

}

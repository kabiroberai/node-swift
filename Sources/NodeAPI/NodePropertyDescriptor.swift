import CNodeAPI

private func cCallback(rawEnv: napi_env!, info: napi_callback_info!, isGetter: Bool) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeFunction.CallbackInfo(raw: info, in: ctx)
        let data = arguments.data
        let callbacks = Unmanaged<NodePropertyDescriptor.Callbacks>.fromOpaque(data).takeUnretainedValue()
        return try (isGetter ? callbacks.value.0 : callbacks.value.1)!(ctx, arguments).rawValue(in: ctx)
    }
}

private func cGetterOrMethod(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    cCallback(rawEnv: rawEnv, info: info, isGetter: true)
}

private func cSetter(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    cCallback(rawEnv: rawEnv, info: info, isGetter: false)
}

public struct NodePropertyDescriptor {
    typealias Callbacks = Box<(getterOrMethod: NodeFunction.Callback?, setter: NodeFunction.Callback?)>

    public struct Attributes: RawRepresentable, OptionSet {
        public let rawValue: CEnum
        public init(rawValue: CEnum) {
            self.rawValue = rawValue
        }

        init(_ raw: napi_property_attributes) {
            self.rawValue = raw.rawValue
        }
        var raw: napi_property_attributes { .init(rawValue) }

        public static let writable = Attributes(napi_writable)
        public static let enumerable = Attributes(napi_enumerable)
        public static let configurable = Attributes(napi_configurable)
        // ignored by define(properties:)
        public static let `static` = Attributes(napi_static)

        public static let `default`: Attributes = []
        public static let defaultMethod: Attributes = [.writable, .configurable]
        public static let defaultProperty: Attributes = [.writable, .enumerable, .configurable]
    }

    public enum Value {
        // not valid for use with defineClass unless static, for some reason
        case data(NodeValueConvertible)
        // we need this because, as mentioned above, `data` isn't valid for
        // defineClass
        case method(NodeFunction.Callback)
        case computed(get: NodeFunction.Callback, set: NodeFunction.Callback)
        case computedGet(NodeFunction.Callback)
        case computedSet(NodeFunction.Callback)
    }

    public let name: NodeName
    public let attributes: Attributes
    public let value: Value

    public init(name: NodeName, attributes: Attributes, value: Value) {
        self.name = name
        self.attributes = attributes
        self.value = value
    }

    // if needed, returns a Callbacks object which must be retained
    // on the object
    func raw(in ctx: NodeContext) throws -> (napi_property_descriptor, Callbacks?) {
        let callbacks: Callbacks?
        var raw = napi_property_descriptor()
        raw.name = try name.rawValue(in: ctx)
        raw.attributes = attributes.raw
        switch value {
        case .data(let data):
            raw.value = try data.rawValue(in: ctx)
            callbacks = nil
        case .method(let method):
            raw.method = cGetterOrMethod
            callbacks = Callbacks((method, nil))
        case .computedGet(let getter):
            raw.getter = cGetterOrMethod
            callbacks = Callbacks((getter, nil))
        case .computedSet(let setter):
            raw.setter = cSetter
            callbacks = Callbacks((nil, setter))
        case let .computed(getter, setter):
            raw.getter = cGetterOrMethod
            raw.setter = cSetter
            callbacks = Callbacks((getter, setter))
        }
        raw.data = callbacks.map { Unmanaged.passUnretained($0).toOpaque() }
        return (raw, callbacks)
    }
}

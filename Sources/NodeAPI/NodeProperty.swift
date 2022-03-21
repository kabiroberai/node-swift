@_implementationOnly import CNodeAPI

@NodeActor(unsafe) private func cCallback(rawEnv: napi_env!, info: napi_callback_info!, isGetter: Bool) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeArguments(raw: info, in: ctx)
        let data = arguments.data
        let callbacks = Unmanaged<NodeProperty.Callbacks>.fromOpaque(data).takeUnretainedValue()
        return try (isGetter ? callbacks.value.0 : callbacks.value.1)!(arguments).rawValue()
    }
}

private func cGetterOrMethod(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    cCallback(rawEnv: rawEnv, info: info, isGetter: true)
}

private func cSetter(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    cCallback(rawEnv: rawEnv, info: info, isGetter: false)
}

public protocol NodePropertyConvertible {
    @NodeActor var nodeProperty: NodeProperty { get }
}

// marker protocol: some values can be represented as properties
// on objects but not on classes (eg non-primitive NodeValues as
// .data)
public protocol NodeClassPropertyConvertible: NodePropertyConvertible {}

public typealias NodePrimitive = NodeValue & NodeClassPropertyConvertible
public typealias NodePrimitiveConvertible = NodeValueConvertible & NodeClassPropertyConvertible

public struct NodePropertyList<Property>: ExpressibleByDictionaryLiteral {
    let elements: [(NodeName, Property)]
    public init(_ elements: [(NodeName, Property)]) {
        self.elements = elements
    }
    public init(dictionaryLiteral elements: (NodeName, Property)...) {
        self.elements = elements
    }
}
public typealias NodeObjectPropertyList = NodePropertyList<NodePropertyConvertible>
public typealias NodeClassPropertyList = NodePropertyList<NodeClassPropertyConvertible>

@NodeActor public struct NodeMethod: NodeClassPropertyConvertible {
    public let nodeProperty: NodeProperty
    public init(attributes: NodeProperty.Attributes = .defaultMethod, _ callback: @escaping NodeFunction.Callback) {
        nodeProperty = .init(attributes: attributes, value: .method(callback))
    }
}

@NodeActor public struct NodeComputedProperty: NodeClassPropertyConvertible {
    public let nodeProperty: NodeProperty
    public init(
        attributes: NodeProperty.Attributes = .defaultProperty,
        get: @escaping NodeFunction.Callback,
        set: NodeFunction.VoidCallback? = nil
    ) {
        var attributes = attributes
        if set == nil {
            // TODO: Is this necessary?
            attributes.remove(.writable)
        }
        nodeProperty = .init(
            attributes: attributes,
            value: set.map { set in
                .computed(get: get) {
                    try set($0)
                    return undefined
                }
            } ?? .computedGet(get)
        )
    }
}

@NodeActor public struct NodeProperty: NodePropertyConvertible {
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
        // ignored by NodeObject.define
        public static let `static` = Attributes(napi_static)

        public static let `default`: Attributes = []
        public static let defaultMethod: Attributes = [.writable, .configurable]
        public static let defaultProperty: Attributes = [.writable, .enumerable, .configurable]
    }

    public enum Value {
        case data(NodeValueConvertible)
        // we need this because you can't use .data for functions
        // while declaring a class prototype
        case method(NodeFunction.Callback)
        case computed(get: NodeFunction.Callback, set: NodeFunction.Callback)
        case computedGet(NodeFunction.Callback)
        case computedSet(NodeFunction.Callback)
    }

    public var nodeProperty: NodeProperty { self }

    public let attributes: Attributes
    public let value: Value

    init(attributes: Attributes, value: Value) {
        self.attributes = attributes
        self.value = value
    }

    public init(attributes: Attributes = .defaultProperty, _ data: NodeValueConvertible) {
        self.attributes = attributes
        self.value = .data(data)
    }

    // when needed, returns a Callbacks object which must be retained
    // on the object
    func raw(name: NodeName) throws -> (napi_property_descriptor, Callbacks?) {
        let callbacks: Callbacks?
        var raw = napi_property_descriptor()
        raw.name = try name.rawValue()
        raw.attributes = attributes.raw
        switch value {
        case .data(let data):
            raw.value = try data.rawValue()
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

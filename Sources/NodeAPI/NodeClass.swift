import CNodeAPI

private typealias ConstructorWrapper = Box<NodeFunction.Callback>

private func cConstructor(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeFunction.Arguments(raw: info, in: ctx)
        let data = arguments.data
        let callbacks = Unmanaged<ConstructorWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callbacks.value(arguments).rawValue()
    }
}

extension NodeFunction {

    public convenience init(
        className: String?,
        properties: NodeClassPropertyList,
        constructor: @escaping NodeFunction.VoidCallback
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
        var name = className ?? ""
        var result: napi_value!
        let ctorWrapper = ConstructorWrapper { args in
            try constructor(args)
            return try NodeUndefined()
        }
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

public protocol NodeClass: AnyObject {
    // mapping from Swift -> JS props
    static var properties: NodeClassPropertyList { get }
    // constructor
    init(_ arguments: NodeFunction.Arguments) throws

    // default implementations provided:
    static var name: String { get }
}

extension NodeClass {
    public static var name: String { "\(self)" }

    static func from(_ args: NodeFunction.Arguments) throws -> Self {
        guard let this = args.this else { throw NodeAPIError(.objectExpected) }
        guard let obj = try this.wrappedValue(forID: ObjectIdentifier(self)) as? Self else {
            throw NodeAPIError(.objectExpected)
        }
        return obj
    }

    // FIXME: Memoize this per env. napi_define_class shouldn't be called more than once.
    public static func constructor() throws -> NodeFunction {
        try NodeFunction(className: name, properties: properties) { args in
            guard let this = args.this else { throw NodeAPIError(.objectExpected) }
            let value = try self.init(args)
            try this.setWrappedValue(value, forID: ObjectIdentifier(self))
        }
    }
}

extension NodeMethod {
    public init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> (NodeFunction.Arguments) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback(T.from($0))($0) }
    }
}

extension NodeComputedProperty {
    public init<T: NodeClass, U: NodeValueConvertible & NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultProperty,
        _ keyPath: KeyPath<T, U>
    ) {
        self.init(attributes: attributes) { try T.from($0)[keyPath: keyPath] }
    }

    public init<T: NodeClass, U: NodeValueConvertible & NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultProperty,
        _ keyPath: ReferenceWritableKeyPath<T, U>
    ) {
        self.init(attributes: attributes) {
            try T.from($0)[keyPath: keyPath]
        } set: { args in
            guard args.count == 1 else { throw NodeAPIError(.invalidArg) }
            guard let converted = try args[0].as(U.self) else {
                throw NodeAPIError(.invalidArg)
            }
            try T.from(args)[keyPath: keyPath] = converted
        }
    }

    public init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultProperty,
        get: @escaping (T) -> () throws -> NodeValueConvertible,
        set: @escaping (T) -> (NodeValue) throws -> Void
    ) {
        self.init(attributes: attributes) {
            try get(T.from($0))()
        } set: { args in
            guard args.count == 1 else { throw NodeAPIError(.invalidArg) }
            try set(T.from(args))(args[0])
        }
    }
}

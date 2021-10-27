@_implementationOnly import CNodeAPI

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

    private static var classID: ObjectIdentifier {
        .init(self)
    }

    static func from(_ args: NodeFunction.Arguments) throws -> Self {
        guard let this = args.this else { throw NodeAPIError(.objectExpected) }
        guard let obj = try this.wrappedValue(forID: classID) as? Self else {
            throw NodeAPIError(.objectExpected)
        }
        return obj
    }

    public static func constructor() throws -> NodeFunction {
        let id = classID
        let env = NodeEnvironment.current
        // we memoize this because we don't want to call napi_define_class multiple
        // times
        if let ctor = try env.instanceData(for: id) as? NodeFunction {
            return ctor
        }
        let newCtor = try NodeFunction(className: name, properties: properties) { args in
            guard let this = args.this else { throw NodeAPIError(.objectExpected) }
            let value = try self.init(args)
            try this.setWrappedValue(value, forID: id)
        }
        try env.setInstanceData(newCtor, for: id)
        return newCtor
    }

    public static var deferredConstructor: NodeValueConvertible {
        NodeDeferredValue { try constructor() }
    }
}

private extension NodeFunction.Arguments {
    func arg<T: NodeValueCreatable>(_ idx: Int) throws -> T {
        guard idx < count else {
            throw try NodeError(code: nil, message: "Function requires at least \(idx + 1) arguments")
        }
        guard let converted = try self[idx].as(T.NodeValueType.self) else {
            throw try NodeError(code: nil, message: "Parameter \(idx) should be of type \(T.NodeValueType.self)")
        }
        return try T(converted)
    }
}

extension NodeMethod {
    public init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> (NodeFunction.Arguments) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback(T.from($0))($0) }
    }

    private init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T, NodeFunction.Arguments) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeFunction.Arguments) in
                try callback(target, args)
            }
        }
    }

    public init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> () throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { target, _ in try callback(target)() }
    }

    public init<T: NodeClass, A0: NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> (A0) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1.arg(0)
        ) }
    }

    public init<T: NodeClass, A0: NodeValueCreatable, A1: NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> (A0, A1) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1.arg(0), $1.arg(1)
        ) }
    }

    public init<T: NodeClass, A0: NodeValueCreatable, A1: NodeValueCreatable, A2: NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> (A0, A1, A2) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1.arg(0), $1.arg(1), $1.arg(2)
        ) }
    }

    public init<T: NodeClass, A0: NodeValueCreatable, A1: NodeValueCreatable, A2: NodeValueCreatable, A3: NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> (A0, A1, A2, A3) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1.arg(0), $1.arg(1), $1.arg(2), $1.arg(3)
        ) }
    }

    public init<T: NodeClass, A0: NodeValueCreatable, A1: NodeValueCreatable, A2: NodeValueCreatable, A3: NodeValueCreatable, A4: NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> (A0, A1, A2, A3, A4) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1.arg(0), $1.arg(1), $1.arg(2), $1.arg(3), $1.arg(4)
        ) }
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
            guard args.count == 1 else {
                throw NodeAPIError(.invalidArg, message: "Expected 1 argument to setter, got \(args.count)")
            }
            guard let converted = try args[0].as(U.self) else {
                throw NodeAPIError(.invalidArg, message: "Coud not convert \(args[0]) to type \(U.self)")
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
            guard args.count == 1 else {
                throw NodeAPIError(.invalidArg, message: "Expected 1 argument to setter, got \(args.count)")
            }
            try set(T.from(args))(args[0])
        }
    }

    public init<T: NodeClass, U: NodeValueConvertible & NodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultProperty,
        get: @escaping (T) -> () throws -> U,
        set: @escaping (T) -> (U) throws -> Void
    ) {
        self.init(attributes: attributes) {
            try get(T.from($0))().nodeValue()
        } set: { args in
            guard args.count == 1 else {
                throw NodeAPIError(.invalidArg, message: "Expected 1 argument to setter, got \(args.count)")
            }
            guard let arg = try args[0].as(U.self) else {
                throw NodeAPIError(.invalidArg, message: "Could not convert \(args[0]) to type \(U.self)")
            }
            try set(T.from(args))(arg)
        }
    }
}

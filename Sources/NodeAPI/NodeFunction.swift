@_implementationOnly import CNodeAPI

private typealias CallbackWrapper = Box<NodeFunction.Callback>

@NodeActor(unsafe) private func cCallback(rawEnv: napi_env!, info: napi_callback_info!) -> napi_value? {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx -> napi_value in
        let arguments = try NodeArguments(raw: info, in: ctx)
        let data = arguments.data
        let callback = Unmanaged<CallbackWrapper>.fromOpaque(data).takeUnretainedValue()
        return try callback.value(arguments).rawValue()
    }
}

public struct NodeArguments: MutableCollection, RandomAccessCollection {
    private var value: [AnyNodeValue]
    public let this: NodeObject?
    public let newTarget: NodeFunction? // new.target
    let data: UnsafeMutableRawPointer

    @NodeActor init(raw: napi_callback_info, in ctx: NodeContext) throws {
        let env = ctx.environment

        var argc: Int = 0
        try env.check(napi_get_cb_info(env.raw, raw, &argc, nil, nil, nil))
        var this: napi_value!
        var data: UnsafeMutableRawPointer!
        let args = try [napi_value?](unsafeUninitializedCapacity: argc) { buf, len in
            len = 0
            try env.check(napi_get_cb_info(env.raw, raw, &argc, buf.baseAddress, &this, &data))
            len = argc
        }.map { AnyNodeValue(raw: $0!, in: ctx) }

        var newTarget: napi_value?
        try env.check(napi_get_new_target(env.raw, raw, &newTarget))

        self.this = try NodeValueBase(raw: this, in: ctx).as(NodeObject.self)
        self.newTarget = try newTarget.flatMap { try NodeValueBase(raw: $0, in: ctx).as(NodeFunction.self) }
        self.data = data
        self.value = args
    }

    public var startIndex: Int { value.startIndex }
    public var endIndex: Int { value.endIndex }
    public func index(after i: Int) -> Int {
        value.index(after: i)
    }

    public subscript(index: Int) -> AnyNodeValue {
        get { value[index] }
        set { value[index] = newValue }
    }
}

public final class NodeFunction: NodeObject, NodeCallable {

    public typealias Callback = @NodeActor (_ arguments: NodeArguments) throws -> NodeValueConvertible
    public typealias VoidCallback = @NodeActor (_ arguments: NodeArguments) throws -> Void
    public typealias AsyncCallback = @NodeActor (_ arguments: NodeArguments) async throws -> NodeValueConvertible
    public typealias AsyncVoidCallback = @NodeActor (_ arguments: NodeArguments) async throws -> Void

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    // this may seem useless since .function is handled in NodeValueType, but
    // consider the following example ("new Function()")
    // try Node.Function.as(NodeFunction.self)!.new().as(NodeFunction.self)
    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        try value.nodeType() == .function
    }

    // TODO: Add a convenience overload for returning Void (convert to NodeUndefined)
    // adding such an overload currently confuses the compiler during overload resolution
    // so we need to figure out how to make it select the right one (@_disfavoredOverload
    // doesn't seem to help)
    public init(name: String = "", callback: @escaping Callback) throws {
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
                        { cCallback(rawEnv: $0, info: $1) },
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

    public convenience init(name: String = "", callback: @escaping VoidCallback) throws {
        try self.init(name: name) { args in
            try callback(args)
            return try NodeUndefined()
        }
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public convenience init(name: String = "", callback: @escaping AsyncCallback) throws {
        try self.init(name: name) { args in
            try NodePromise { try await callback(args) }
        }
    }

    public convenience init(name: String = "", callback: @escaping AsyncVoidCallback) throws {
        try self.init(name: name) { args in
            try await callback(args)
            return try NodeUndefined()
        }
    }

    @discardableResult
    public func call(
        on receiver: NodeValueConvertible = undefined,
        _ arguments: [NodeValueConvertible]
    ) throws -> AnyNodeValue {
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
        return AnyNodeValue(raw: ret)
    }

    public func construct(withArguments arguments: [NodeValueConvertible]) throws -> NodeObject {
        let env = base.environment
        let argv: [napi_value?] = try arguments.map { try $0.rawValue() }
        var result: napi_value!
        try env.check(
            napi_new_instance(env.raw, base.rawValue(), arguments.count, argv, &result)
        )
        return try NodeValueBase(raw: result, in: .current).as(NodeObject.self)!
    }

}

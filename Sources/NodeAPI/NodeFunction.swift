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
    private var value: [NodeValue]
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

    public subscript(index: Int) -> NodeValue {
        get { value[index] }
        set { value[index] = newValue }
    }

    // TODO: Should we make this public? It might confuse users,
    // since we usually recommend using .as but here they'd be
    // expected to do something like `try args[0] as String`
    @NodeActor subscript<T: AnyNodeValueCreatable>(index: Int) -> T {
        get throws {
            if index < count {
                guard let converted = try self[index].as(T.self) else {
                    throw try NodeError(code: nil, message: "Could not convert parameter \(index) to type \(T.self)")
                }
                return converted
            } else {
                // if we're asking for an arg that's out of bounds,
                // return the equivalent of `undefined` if possible,
                // else throw
                guard let converted = try undefined.as(T.self) else {
                    throw try NodeError(code: nil, message: "Function requires at least \(index + 1) arguments")
                }
                return converted
            }
        }
    }
}

@dynamicCallable
public final class NodeFunction: NodeObject {

    public typealias Callback = @NodeActor (_ arguments: NodeArguments) throws -> NodeValueConvertible
    public typealias VoidCallback = @NodeActor (_ arguments: NodeArguments) throws -> Void

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    // this may seem useless since .function is handled in NodeValueType, but
    // consider the following example ("new Function()")
    // try env.global().Function.as(NodeFunction.self)!.new().as(NodeFunction.self)
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

    @discardableResult
    public func call(
        on receiver: NodeValueConvertible = undefined,
        _ arguments: [NodeValueConvertible]
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
        return AnyNodeValue(raw: ret)
    }

    // we can't use callAsFunction(_ args: NodeValueConvertible...) because if
    // you pass it a [NodeValueConvertible] it parses it as the entire args list
    // instead of as a single argument. Weird bug but ok.
    @discardableResult
    public func dynamicallyCall(withArguments args: [NodeValueConvertible]) throws -> NodeValue {
        try call(args)
    }

    public func new(arguments: [NodeValueConvertible]) throws -> NodeObject {
        let env = base.environment
        let argv: [napi_value?] = try arguments.map { try $0.rawValue() }
        var result: napi_value!
        try env.check(
            napi_new_instance(env.raw, base.rawValue(), arguments.count, argv, &result)
        )
        return try NodeValueBase(raw: result, in: .current).as(NodeObject.self)!
    }

    public func new(_ arguments: NodeValueConvertible...) throws -> NodeObject {
        try new(arguments: arguments)
    }

}

extension NodeFunction {

    public convenience init(name: String = "", callback: @escaping @NodeActor () throws -> NodeValueConvertible) throws {
        try self.init(name: name) { _ in
            try callback()
        }
    }

    public convenience init<A0: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6], $0[7])
        }
    }

}

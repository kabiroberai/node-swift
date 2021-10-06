import CNodeAPI

private extension NodeEnvironment {
    private static let releaseQueueKey =
        NodeInstanceDataKey<NodeAsyncQueue>()

    func getReleaseQueue() throws -> NodeAsyncQueue {
        if let q = try instanceData(for: Self.releaseQueueKey) {
            return q
        }
        let q = try NodeAsyncQueue(
            label: "NAPI_SWIFT_RELEASE_REF",
            keepsNodeThreadAlive: false
        )
        try setInstanceData(q, for: Self.releaseQueueKey)
        return q
    }
}

@_spi(NodeAPI) public final class NodeValueBase {
    private enum Guts {
        case unmanaged(napi_value)
        case managed(napi_ref, releaseQueue: NodeAsyncQueue, isBoxed: Bool)
    }

    let environment: NodeEnvironment
    private var guts: Guts
    // we take in a ctx here instead of using .current, since a ctx is
    // probably already available to the caller
    init(raw: napi_value, in ctx: NodeContext) {
        self.guts = .unmanaged(raw)
        self.environment = ctx.environment
        // this isn't the most performant solution to escaping NodeValues but
        // it's worth noting that even JSC seems to do something similar:
        // https://github.com/WebKit/WebKit/blob/dc23fbec330747c0fcd0e068c9103c05c65e4bf1/Source/JavaScriptCore/API/JSWrapperMap.mm#L641-L673
        // Also if users really need performance they can use
        // NodeEnvironment.withUnmanaged
        ctx.registerValue(self)
    }

    // TODO: Figure out if/where this is needed:
    // If a value is "owned" by some object, and we create an unmanaged ref
    // to it, could it be garbage collected while the user still needs it?
    init(managedRaw raw: napi_value, in ctx: NodeContext) throws {
        self.guts = .unmanaged(raw)
        self.environment = ctx.environment
        // don't register with ctx here; doing so would include the
        // receiver in the check for whether it escaped
        try persist()
    }

    func persist() throws {
        switch guts {
        case .managed:
            break // already persisted
        case .unmanaged(let raw):
            let boxedRaw: napi_value
            let isBoxed: Bool
            if try NodeObject.isObjectType(for: self) {
                boxedRaw = raw
                isBoxed = false
            } else {
                // we can't create a ref out of a non-object so box the value
                // into an object with the actual value at obj[0]. Use NAPI
                // APIs directly to avoid causing recursion
                var obj: napi_value!
                try environment.check(napi_create_object(environment.raw, &obj))
                try environment.check(napi_set_element(environment.raw, obj, 0, raw))
                boxedRaw = obj
                isBoxed = true
            }
            var ref: napi_ref!
            try environment.check(napi_create_reference(environment.raw, boxedRaw, 1, &ref))
            let releaseQueue = try environment.getReleaseQueue()
            self.guts = .managed(ref, releaseQueue: releaseQueue, isBoxed: isBoxed)
        }
    }

    func rawValue() throws -> napi_value {
        switch guts {
        case .unmanaged(let val):
            return val
        case .managed(let ref, _, let isBoxed):
            var val: napi_value!
            try environment.check(napi_get_reference_value(environment.raw, ref, &val))
            if isBoxed {
                var result: napi_value!
                try environment.check(napi_get_element(environment.raw, val, 0, &result))
                return result
            } else {
                return val
            }
        }
    }

    deinit {
        // this can be called on any thread, so we can't just use `environment`
        // directly here. Instead, we utilize a threadsafe release function
        switch guts {
        case .unmanaged:
            break
        case let .managed(ref, releaseQueue, _):
            try? releaseQueue.async {
                let env = NodeEnvironment.current
                try env.check(
                    napi_delete_reference(env.raw, ref)
                )
            }
        }
    }
}

// MARK: - Protocols

public protocol NodeValueConvertible {
    func nodeValue() throws -> NodeValue
}

extension NodeValueConvertible {
    func rawValue() throws -> napi_value {
        try nodeValue().base.rawValue()
    }
}

public protocol NodeName: NodeValueConvertible {}
public protocol NodeObjectConvertible: NodeValueConvertible {}

public protocol NodeValue: NodeValueConvertible, CustomStringConvertible {
    @_spi(NodeAPI) var base: NodeValueBase { get }
    @_spi(NodeAPI) init(_ base: NodeValueBase)
}

public protocol NodeValueCoercible: NodeValue {
    init(coercing value: NodeValueConvertible) throws
}

extension NodeValue {
    public func nodeValue() throws -> NodeValue { self }

    public var description: String {
        let desc = try? NodeContext.withUnmanagedContext(environment: base.environment) { ctx -> String in
            try NodeString(coercing: self).string()
        }
        return desc ?? "<invalid \(Self.self)>"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        var isEqual = false
        try? NodeContext.withUnmanagedContext(environment: lhs.base.environment) { ctx in
            try ctx.environment.check(
                napi_strict_equals(
                    ctx.environment.raw,
                    lhs.base.rawValue(),
                    rhs.base.rawValue(),
                    &isEqual
                )
            )
        }
        return isEqual
    }
}

// We could technically piggyback off WeakMap to get Hashable support
// by creating an obj => number mapping (where the number can simply
// be the current size of the map at the time of insertion).
// But even though that's O(1), there's a large constant factor +
// the possibility for node to throw exceptions, which complicates
// matters. But maybe someday.
// TODO: Use this
protocol ConcreteNodeValue: NodeValue, Equatable {}

// MARK: - Value Types

enum NodeValueType {
    struct UnknownTypeError: Error {
        let type: napi_valuetype
    }

    case undefined
    case null
    case boolean
    case number
    case string
    case symbol
    case object
    case function
    case external
    case bigint

    init(raw: napi_valuetype) throws {
        switch raw {
        case napi_undefined:
            self = .undefined
        case napi_null:
            self = .null
        case napi_boolean:
            self = .boolean
        case napi_number:
            self = .number
        case napi_string:
            self = .string
        case napi_symbol:
            self = .symbol
        case napi_object:
            self = .object
        case napi_function:
            self = .function
        case napi_external:
            self = .external
        case napi_bigint:
            self = .bigint
        default:
            throw UnknownTypeError(type: raw)
        }
    }

    var concreteType: NodeValue.Type {
        switch self {
        case .undefined:
            return NodeUndefined.self
        case .null:
            return NodeNull.self
        case .boolean:
            return NodeBool.self
        case .number:
            return NodeNumber.self
        case .string:
            return NodeString.self
        case .symbol:
            return NodeSymbol.self
        case .external:
            return NodeExternal.self
        case .bigint:
            return NodeBigInt.self
        case .function:
            return NodeFunction.self
        case .object:
            return NodeObject.self
        }
    }
}

extension NodeValueBase {

    func type() throws -> NodeValueType {
        var type = napi_undefined
        try environment.check(napi_typeof(environment.raw, rawValue(), &type))
        return try NodeValueType(raw: type)
    }

    func concrete() throws -> NodeValue {
        try type().concreteType.init(self)
    }

    func `as`<T: NodeValue>(_ type: T.Type) throws -> T? {
        if try self.type().concreteType == type {
            return T(self)
        } else if let objectType = type as? NodeObject.Type {
            guard try objectType.isObjectType(for: self) else {
                return nil
            }
            return T(self)
        } else {
            return nil
        }
    }

}

extension NodeValue {

    func type() throws -> NodeValueType {
        try base.type()
    }

    // TODO: Ideally, NodeObject would be a class cluster such that
    // (for example) initializing a NodeObject with a Date type would
    // return a NodeDate. Doing that would allow casting with normal
    // Swift syntax like `as?` instead of using this. But we should
    // first figure out an efficient way to determine which type an
    // object is.
    //
    // Also, maybe NodeValueBase could have a private initializer, and
    // all code would have to go through a static method such as
    // `NodeValueBase.create(raw:in:) -> NodeValue` in order to create
    // a value. The create method would check the type() and return an
    // instance of the appropriate class.
    public func `as`<T: NodeValue>(_ type: T.Type) throws -> T? {
        try base.as(T.self)
    }

}

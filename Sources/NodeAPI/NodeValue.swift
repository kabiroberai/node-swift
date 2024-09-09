@_implementationOnly import CNodeAPI

@_spi(NodeAPI) @NodeActor public final class NodeValueBase {
    private enum Guts: @unchecked Sendable {
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

    func persist(releaseQueue: NodeAsyncQueue? = nil) throws {
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
            let releaseQueue = try releaseQueue ?? environment.getDefaultQueue()
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
        // this can be called on any thread, so we rely on a NodeAsyncQueue
        // when we need to access the current env.
        switch guts {
        case .unmanaged:
            break
        case let .managed(ref, releaseQueue, _):
            let sendable = UncheckedSendable(ref)
            try? releaseQueue.run {
                let env = NodeEnvironment.current
                try env.check(
                    napi_delete_reference(env.raw, sendable.value)
                )
            }
        }
    }
}

// MARK: - Protocols

public protocol NodeValueConvertible: NodePropertyConvertible {
    @NodeActor func nodeValue() throws -> NodeValue
}

// Utility for APIs that take NodeValueConvertible: useful when you
// want to defer NodeValue creation to the API, for example if you don't
// want to throw in your own code or if you're on a non-JS thread
public struct NodeDeferredValue: NodeValueConvertible, Sendable {
    let wrapper: @Sendable @NodeActor () throws -> NodeValue

    // thread-safe
    public init(_ wrapper: @escaping @Sendable @NodeActor () throws -> NodeValue) {
        self.wrapper = wrapper
    }

    @NodeActor public func nodeValue() throws -> NodeValue {
        try wrapper()
    }
}

// Utility for APIs that take NodeValueConvertible: useful when you
// want to defer NodeValue creation to the API, for example for
// accessing global or well-known Symbols.
public struct NodeDeferredName: NodeValueConvertible, Sendable, NodeName {
    let wrapper: @Sendable @NodeActor () throws -> NodeValue

    // thread-safe
    public init(_ wrapper: @escaping @Sendable @NodeActor () throws -> NodeValue) {
        self.wrapper = wrapper
    }

    @NodeActor public func nodeValue() throws -> NodeValue {
        try wrapper()
    }
}

public protocol AnyNodeValueCreatable {
    @NodeActor static func from(_ value: NodeValue) throws -> Self?
}

// for when ValueType is losslessly convertible to Self
// (modulo errors)
public protocol NodeValueCreatable: AnyNodeValueCreatable {
    associatedtype ValueType: NodeValue
    @NodeActor static func from(_ value: ValueType) throws -> Self
}

extension NodeValueCreatable {
    @NodeActor public static func from(_ value: NodeValue) throws -> Self? {
        // calls the strongly typed from(_:) after converting
        // to ValueType
        try value.as(ValueType.self).map { try from($0) }
    }
}

extension NodeValueConvertible {
    @NodeActor public var nodeProperty: NodePropertyBase {
        NodePropertyBase(attributes: .defaultProperty, value: .data(self))
    }

    @NodeActor func rawValue() throws -> napi_value {
        try nodeValue().base.rawValue()
    }
}

public protocol NodeName: NodeValueConvertible {}
public protocol NodeObjectConvertible: NodeValueConvertible {}

@NodeActor public protocol NodeValue: NodeValueConvertible, AnyNodeValueCreatable, CustomStringConvertible, Error {
    @_spi(NodeAPI) var base: NodeValueBase { get }
    @_spi(NodeAPI) init(_ base: NodeValueBase)
}

@dynamicCallable
@NodeActor public protocol NodeCallable: NodeValueConvertible {
    @_spi(NodeAPI) var receiver: NodeValueConvertible { get }
}
extension NodeCallable {
    @_spi(NodeAPI) public var receiver: NodeValueConvertible { undefined }

    // we can't use callAsFunction(_ args: NodeValueConvertible...) because if
    // you pass it a [NodeValueConvertible] there's a bug where it parses it as
    // the entire args list instead of as a single argument
    @discardableResult
    public func dynamicallyCall(withArguments args: [NodeValueConvertible]) throws -> AnyNodeValue {
        guard let fn = try self.as(NodeFunction.self) else {
            throw NodeAPIError(.functionExpected, message: "Cannot call a non-function: \(try debugDescription())")
        }
        return try fn.call(on: receiver, args)
    }

    public var new: NodeCallableConstructor {
        NodeCallableConstructor(callable: self)
    }

    internal func debugDescription() throws -> String {
        let actual = "\(try self.nodeValue()) (\(self))"
        if let dynamicProperty = self as? NodeObject.DynamicProperty {
            return "\(receiver).\(dynamicProperty.key) is \(actual)"
        }
        return "is \(actual)"
    }
}

// this type exists due to the aforementioned callAsFunction bug
@dynamicCallable
@NodeActor public struct NodeCallableConstructor {
    let callable: NodeCallable
    public func dynamicallyCall(withArguments args: [NodeValueConvertible]) throws -> NodeObject {
        guard let fn = try callable.as(NodeFunction.self) else {
            throw NodeAPIError(.functionExpected, message: "Cannot call a non-function as constructor: \(try callable.debugDescription())")
        }
        return try fn.construct(withArguments: args)
    }
}

@dynamicMemberLookup
@NodeActor public protocol NodeLookupable: NodeValueConvertible {}
extension NodeLookupable {
    public subscript(key: NodeValueConvertible) -> NodeObject.DynamicProperty {
        get throws {
            try NodeObject(coercing: self).property(forKey: key)
        }
    }

    public subscript(dynamicMember key: String) -> NodeObject.DynamicProperty {
        get throws {
            try NodeObject(coercing: self).property(forKey: key)
        }
    }
}

extension NodeValue {
    @_spi(NodeAPI) public var base: NodeValueBase { 
        fatalError("Custom implementations of NodeValue are unsupported")
    }

    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        fatalError("Custom implementations of NodeValue are unsupported")
    }
}

public protocol NodeValueCoercible: NodeValue {
    @NodeActor init(coercing value: NodeValueConvertible) throws
}

extension NodeValue {
    public func nodeValue() throws -> NodeValue { self }

    public nonisolated var description: String {
        (try? NodeContext.runOnActor { try NodeString(coercing: self).string() }) ?? "<\(Self.self)>"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        var isEqual = false
        let env = lhs.base.environment
        try? env.check(
            napi_strict_equals(
                env.raw,
                lhs.base.rawValue(),
                rhs.base.rawValue(),
                &isEqual
            )
        )
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

public enum NodeValueType {
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

    func nodeType() throws -> NodeValueType {
        var type = napi_undefined
        try environment.check(napi_typeof(environment.raw, rawValue(), &type))
        return try NodeValueType(raw: type)
    }

    func `as`<T: NodeValue>(_ type: T.Type) throws -> T? {
        if try type == AnyNodeValue.self || type == nodeType().concreteType {
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
    // instance of the appropriate class. Accordingly, we'd replace all
    // occurrences of AnyNodeValue.init with this API.
    public static func from(_ value: NodeValue) throws -> Self? {
        // TODO: Maybe throw TypeError if casting fails instead of returning nil?
        try value.base.as(Self.self)
    }

}

extension NodeValueConvertible {

    @NodeActor public func nodeType() throws -> NodeValueType {
        try nodeValue().base.nodeType()
    }

    @NodeActor public func `as`<T: AnyNodeValueCreatable>(_ type: T.Type) throws -> T? {
        let val = try nodeValue()
        // just a short circuit for perf reasons
        return try (val as? T) ?? T.from(val)
    }

    @NodeActor public func `as`<T: NodeValueCreatable>(_ type: T.Type) throws -> T where T.ValueType == Self {
        try (self as? T) ?? T.from(self)
    }

    @NodeActor public func `as`(_ type: AnyNodeValue.Type) throws -> AnyNodeValue {
        try AnyNodeValue(nodeValue())
    }

    // Array itself conforms to NodeValueCreatable iff Element == NodeValue, i.e.
    // for [NodeValue]. This means that specializations, like [String], don't
    // themselves have this conformance. Consequently, this function special-cases
    // those situations to allow for stuff like foo.as([String].self). Unfortunately
    // this doesn't nest, i.e. you can't do as([[String]].self), since T: [String]
    // itself doesn't conform to NodeValueCreatable
    //
    // (we could also switch the conformances around, but then [[String]] would work
    // whereas [[NodeValue]] wouldn't)
    @NodeActor public func `as`<T: NodeValueCreatable>(_ type: [T].Type) throws -> [T]? {
        do {
            return try self.as([NodeValue].self)?.map {
                guard let t = try $0.as(T.self) else { throw NilValueError() }
                return t
            }
        } catch is NilValueError {
            return nil
        }
    }

    @NodeActor public func `as`<T: NodeValueCreatable>(_ type: [String: T].Type) throws -> [String: T]? {
        do {
            return try self.as([String: NodeValue].self)?.mapValues {
                guard let t = try $0.as(T.self) else { throw NilValueError() }
                return t
            }
        } catch is NilValueError {
            return nil
        }
    }

}

// when we have an untyped napi_value and we want an opaque NodeValue
// (the user can inspect the type with nodeType() and/or cast accordingly
// using .as())
public struct AnyNodeValue: NodeValue, NodeCallable, NodeLookupable {
    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }

    public init(_ value: NodeValue) {
        self.base = value.base
    }

    init(raw: napi_value, in ctx: NodeContext = .current) {
        self.base = NodeValueBase(raw: raw, in: ctx)
    }
}

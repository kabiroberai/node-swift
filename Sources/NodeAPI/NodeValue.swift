import CNodeAPI

@_spi(NodeAPI) public final class NodeValueBase {
    private enum Guts {
        case unmanaged(napi_value)
        case managed(napi_ref, NodeEnvironment.InstanceData)
    }

    let environment: NodeEnvironment
    private var guts: Guts
    init(raw: napi_value, in ctx: NodeContext) {
        self.guts = .unmanaged(raw)
        self.environment = ctx.environment
        // this isn't the most performant solution to escaping NodeValues but
        // it's worth noting that even JSC seems to do something similar:
        // https://github.com/WebKit/WebKit/blob/dc23fbec330747c0fcd0e068c9103c05c65e4bf1/Source/JavaScriptCore/API/JSWrapperMap.mm
        // Also if users really need performance they can use
        // NodeEnvironment.withUnmanaged
        ctx.registerValue(self)
    }

    func `as`<T: NodeValue>(_ type: T.Type) -> T {
        T(self)
    }

    func persist() throws {
        switch guts {
        case .managed:
            break // already persisted
        case .unmanaged(let raw):
            var ref: napi_ref!
            try environment.check(napi_create_reference(environment.raw, raw, 1, &ref))
            self.guts = .managed(ref, try environment.instanceData())
        }
    }

    func rawValue() throws -> napi_value {
        switch guts {
        case .unmanaged(let val):
            return val
        case .managed(let ref, _):
            var val: napi_value!
            try environment.check(napi_get_reference_value(environment.raw, ref, &val))
            return val
        }
    }

    deinit {
        // this can be called on any thread, so we can't just use `environment`
        // directly here.
        // TODO: Use napi_threadsafe_function instead of the deadRef strategy
        switch guts {
        case .unmanaged:
            break
        case let .managed(ref, instanceData):
            instanceData.addDeadRef(ref)
        }
    }
}

// MARK: - Protocols

public protocol NodeValueConvertible {
    func nodeValue(in ctx: NodeContext) throws -> NodeValue
}

extension NodeValueConvertible {
    func rawValue(in ctx: NodeContext) throws -> napi_value {
        try nodeValue(in: ctx).base.rawValue()
    }
}

public protocol NodeName: NodeValueConvertible {}

public protocol NodeValue: NodeValueConvertible, CustomStringConvertible {
    @_spi(NodeAPI) var base: NodeValueBase { get }
    @_spi(NodeAPI) init(_ base: NodeValueBase)
}

public protocol NodeValueCoercible: NodeValue {
    init(coercing value: NodeValueConvertible, in ctx: NodeContext) throws
}

extension NodeValue {
    public func nodeValue(in ctx: NodeContext) throws -> NodeValue { self }

    public func `as`<T: NodeValue>(_ type: T.Type) -> T { T(base) }

    public var description: String {
        let desc = try? NodeContext.withUnmanagedContext(environment: base.environment) { ctx -> String in
            try NodeString(coercing: self, in: ctx).string()
        }
        return desc ?? "\(Self.self)"
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
protocol ConcreteNodeValue: NodeValue, Equatable {}

public struct AnyNodeValue: ConcreteNodeValue {
    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }
}

// MARK: - Value Types

public enum NodeValueType {
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

    init?(raw: napi_valuetype) {
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
            return nil
        }
    }
}

extension NodeValue {

    public func type() throws -> NodeValueType {
        var type = napi_undefined
        try base.environment.check(napi_typeof(base.environment.raw, base.rawValue(), &type))
        return NodeValueType(raw: type)!
    }

}

// MARK: - Finalizers

private class FinalizeWrapper {
    let finalizer: (NodeContext) throws -> Void
    init(finalizer: @escaping (NodeContext) throws -> Void) {
        self.finalizer = finalizer
    }
}

private func cFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer!) {
    try? NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        try Unmanaged<FinalizeWrapper>
            .fromOpaque(data)
            .takeRetainedValue() // releases the wrapper post-call
            .finalizer(ctx)
    }
}

extension NodeValue {

    public func addFinalizer(_ finalizer: @escaping (NodeContext) throws -> Void) throws {
        let data = Unmanaged.passRetained(FinalizeWrapper(finalizer: finalizer)).toOpaque()
        try base.environment.check(
            napi_add_finalizer(base.environment.raw, base.rawValue(), data, cFinalizer, nil, nil)
        )
    }

}

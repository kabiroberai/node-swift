import CNodeAPI

public final class NodeValue: NodeValueConvertible, CustomStringConvertible {
    private enum Guts {
        case unmanaged(napi_value)
        case managed(napi_ref, NodeEnvironment.InstanceData)
    }

    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        self
    }

    public var description: String {
        let desc = try? NodeContext.withUnmanagedContext(environment: environment) { ctx -> String in
            try NodeString(coercing: self, in: ctx).string()
        }
        return desc ?? "<unknown NodeValue>"
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

    public func `as`<T: NodeValueStorage>(_ type: T.Type) -> T {
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

public protocol NodeName: NodeValueConvertible {}

public protocol NodeValueStorage: NodeValueConvertible, CustomStringConvertible {
    var storedValue: NodeValue { get }
    init(_ storedValue: NodeValue)
}

extension NodeValueStorage {
    public init(_ value: NodeValueConvertible, in ctx: NodeContext) throws {
        try self.init(value.nodeValue(in: ctx))
    }

    public var description: String { "\(storedValue)" }

    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        storedValue
    }

    public func `as`(_ type: NodeValue.Type) -> NodeValue {
        storedValue
    }

    public func `as`<T: NodeValueStorage>(_ type: T.Type) -> T {
        T(storedValue)
    }
}

protocol NodeValueLiteral: NodeValueConvertible {
    associatedtype Storage: NodeValueStorage
    func storage(in ctx: NodeContext) throws -> Storage
}

extension NodeValueLiteral {
    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        try storage(in: ctx).storedValue
    }
}

// MARK: - Value Types

extension NodeValue {

    public enum ValueType {
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

    public func type() throws -> ValueType {
        var type = napi_undefined
        try environment.check(napi_typeof(environment.raw, rawValue(), &type))
        return ValueType(raw: type)!
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
        try environment.check(napi_add_finalizer(environment.raw, rawValue(), data, cFinalizer, nil, nil))
    }

}

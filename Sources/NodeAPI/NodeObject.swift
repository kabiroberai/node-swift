import CNodeAPI
import Foundation

@dynamicMemberLookup
public class NodeObject: NodeValue, NodeObjectConvertible {

    @_spi(NodeAPI) public final let base: NodeValueBase
    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        self.base = base
    }

    class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let type = try value.type()
        return type == .object || type == .function
    }

    public init(coercing value: NodeValueConvertible, in ctx: NodeContext) throws {
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(napi_coerce_to_object(env.raw, value.rawValue(in: ctx), &coerced))
        self.base = NodeValueBase(raw: coerced, in: ctx)
    }

    public init(in ctx: NodeContext, constructor: NodeFunction, arguments: [NodeValueConvertible] = []) throws {
        let env = ctx.environment
        let argv = try arguments.map { arg -> napi_value? in try arg.rawValue(in: ctx) }
        var result: napi_value!
        try env.check(
            napi_new_instance(env.raw, constructor.base.rawValue(), arguments.count, argv, &result)
        )
        self.base = NodeValueBase(raw: result, in: ctx)
    }

    public init(in ctx: NodeContext) throws {
        let env = ctx.environment
        var obj: napi_value!
        try env.check(napi_create_object(env.raw, &obj))
        base = NodeValueBase(raw: obj, in: ctx)
    }

    public final func isInstance(of constructor: NodeFunction) throws -> Bool {
        var result = false
        try base.environment.check(
            napi_instanceof(base.environment.raw, base.rawValue(), constructor.base.rawValue(), &result)
        )
        return result
    }

}

extension Dictionary: NodeValueConvertible, NodeObjectConvertible where Key == String, Value: NodeValueConvertible {
    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        let obj = try NodeObject(in: ctx)
        try obj.define(properties: map {
            NodePropertyDescriptor(name: $0, attributes: .defaultProperty, value: .data($1))
        })
        return obj
    }
}

// MARK: - Properties

extension NodeObject {

    @dynamicMemberLookup
    public final class DynamicProperty {
        let environment: NodeEnvironment
        let key: NodeValueConvertible
        // Defer resolution until it's necessary. This allows users
        // to chain dynamic lookups without needing to pass in a
        // new context for each call
        let resolveObject: (NodeContext) throws -> NodeObject

        init(
            environment: NodeEnvironment,
            key: NodeValueConvertible,
            resolveObject: @escaping (NodeContext) throws -> NodeObject
        ) {
            self.environment = environment
            self.key = key
            self.resolveObject = resolveObject
        }

        public func get(in ctx: NodeContext) throws -> NodeValue {
            var ret: napi_value!
            try ctx.environment.check(
                napi_get_property(
                    ctx.environment.raw,
                    resolveObject(ctx).base.rawValue(),
                    key.rawValue(in: ctx),
                    &ret
                )
            )
            return try NodeValueBase(raw: ret, in: ctx).concrete()
        }

        public func set(to value: NodeValueConvertible) throws {
            try NodeContext.withUnmanagedContext(environment: environment) { ctx in
                _ = try ctx.environment.check(napi_set_property(
                    ctx.environment.raw,
                    resolveObject(ctx).base.rawValue(),
                    key.rawValue(in: ctx),
                    value.rawValue(in: ctx)
                ))
            }
        }

        @discardableResult
        public func delete() throws -> Bool {
            var result = false
            try NodeContext.withUnmanagedContext(environment: environment) { ctx in
                try ctx.environment.check(napi_delete_property(
                    ctx.environment.raw,
                    resolveObject(ctx).base.rawValue(),
                    key.rawValue(in: ctx),
                    &result
                ))
            }
            return result
        }

        public func exists() throws -> Bool {
            var result = false
            try NodeContext.withUnmanagedContext(environment: environment) { ctx in
                try ctx.environment.check(napi_has_property(
                    ctx.environment.raw,
                    resolveObject(ctx).base.rawValue(),
                    key.rawValue(in: ctx),
                    &result
                ))
            }
            return result
        }

        @discardableResult
        public func callAsFunction(in ctx: NodeContext, _ args: NodeValueConvertible...) throws -> NodeValue {
            guard let fn = try self.get(in: ctx).as(NodeFunction.self) else {
                throw NodeAPIError(.functionExpected)
            }
            return try fn.call(in: ctx, receiver: resolveObject(ctx), arguments: args)
        }

        public func property(forKey key: NodeValueConvertible) -> DynamicProperty {
            DynamicProperty(environment: environment, key: key) {
                guard let obj = try self.get(in: $0).as(NodeObject.self) else {
                    throw NodeAPIError(.objectExpected)
                }
                return obj
            }
        }

        public subscript(key: NodeValueConvertible) -> DynamicProperty {
            property(forKey: key)
        }

        public subscript(dynamicMember key: String) -> DynamicProperty {
            property(forKey: key)
        }
    }

    public final func property(forKey key: NodeValueConvertible) -> DynamicProperty {
        DynamicProperty(environment: base.environment, key: key) { _ in self }
    }

    public final subscript(key: NodeValueConvertible) -> DynamicProperty {
        property(forKey: key)
    }

    public final subscript(dynamicMember key: String) -> DynamicProperty {
        property(forKey: key)
    }

    public final func hasOwnProperty(_ key: NodeName) throws -> Bool {
        var result = false
        try NodeContext.withUnmanagedContext(environment: base.environment) { ctx in
            try ctx.environment.check(napi_has_own_property(
                ctx.environment.raw,
                base.rawValue(),
                key.rawValue(in: ctx),
                &result
            ))
        }
        return result
    }

    public enum KeyCollectionMode {
        case includePrototypes
        case ownOnly

        var raw: napi_key_collection_mode {
            switch self {
            case .includePrototypes:
                return napi_key_include_prototypes
            case .ownOnly:
                return napi_key_own_only
            }
        }
    }

    public enum KeyConversion {
        case keepNumbers
        case numbersToStrings

        var raw: napi_key_conversion {
            switch self {
            case .keepNumbers:
                return napi_key_keep_numbers
            case .numbersToStrings:
                return napi_key_numbers_to_strings
            }
        }
    }

    public struct KeyFilter: RawRepresentable, OptionSet {
        public let rawValue: CEnum
        public init(rawValue: CEnum) {
            self.rawValue = rawValue
        }

        init(_ raw: napi_key_filter) {
            self.rawValue = raw.rawValue
        }
        var raw: napi_key_filter { .init(rawValue) }

        public static let allProperties = KeyFilter(napi_key_all_properties)
        public static let writable = KeyFilter(napi_key_writable)
        public static let enumerable = KeyFilter(napi_key_enumerable)
        public static let configurable = KeyFilter(napi_key_configurable)
        public static let skipStrings = KeyFilter(napi_key_skip_strings)
        public static let skipSymbols = KeyFilter(napi_key_skip_symbols)
    }

    public final func propertyNames(
        collectionMode: KeyCollectionMode,
        filter: KeyFilter,
        conversion: KeyConversion,
        in ctx: NodeContext
    ) throws -> NodeArray {
        var result: napi_value!
        try ctx.environment.check(
            napi_get_all_property_names(
                ctx.environment.raw,
                base.rawValue(),
                collectionMode.raw,
                filter.raw,
                conversion.raw,
                &result
            )
        )
        return NodeArray(NodeValueBase(raw: result, in: ctx))
    }

    public final func define(properties: [NodePropertyDescriptor]) throws {
        try NodeContext.withUnmanagedContext(environment: base.environment) { ctx in
            let env = ctx.environment
            var descriptors: [napi_property_descriptor] = []
            var callbacks: [NodePropertyDescriptor.Callbacks] = []
            for prop in properties {
                let (desc, cb) = try prop.raw(in: ctx)
                descriptors.append(desc)
                if let cb = cb {
                    callbacks.append(cb)
                }
            }
            try env.check(napi_define_properties(env.raw, base.rawValue(), properties.count, descriptors))
            if !callbacks.isEmpty {
                // retain new callbacks
                try addFinalizer { _ in _ = callbacks }
            }
        }
    }

    public final func prototype(in ctx: NodeContext) throws -> NodeValue {
        let env = ctx.environment
        var result: napi_value!
        try env.check(napi_get_prototype(env.raw, base.rawValue(), &result))
        return try NodeValueBase(raw: result, in: ctx).concrete()
    }

    #if !NAPI_VERSIONED || NAPI_GE_8
    public final func freeze() throws {
        try base.environment.check(
            napi_object_freeze(
                base.environment.raw,
                base.rawValue()
            )
        )
    }

    public final func seal() throws {
        try base.environment.check(
            napi_object_seal(
                base.environment.raw,
                base.rawValue()
            )
        )
    }
    #endif

}

// MARK: - Object Wrap

#if !NAPI_VERSIONED || NAPI_GE_8

public final class NodeWrappedDataKey<T> {
    public init() {}
}

private typealias WrappedData = Box<[ObjectIdentifier: Any]>

private func cWrapFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer!) {
    Unmanaged<WrappedData>.fromOpaque(data).release()
}

extension NodeObject {

    // we could make this public but its functionality can pretty much be
    // replicated by the wrapped value stuff

    private func withTypeTag<T>(_ tag: UUID, do action: (UnsafePointer<napi_type_tag>) throws -> T) rethrows -> T {
        try withUnsafePointer(to: tag.uuid) {
            try $0.withMemoryRebound(to: napi_type_tag.self, capacity: 1, action)
        }
    }

    // can be called at most once per value
    fileprivate func setTypeTag(_ tag: UUID) throws {
        let env = base.environment
        try withTypeTag(tag) {
            try env.check(
                napi_type_tag_object(
                    env.raw, base.rawValue(), $0
                )
            )
        }
    }

    fileprivate func hasTypeTag(_ tag: UUID) throws -> Bool {
        let env = base.environment
        var result = false
        try withTypeTag(tag) {
            try env.check(
                napi_check_object_type_tag(
                    env.raw, base.rawValue(), $0, &result
                )
            )
        }
        return result
    }

}

extension NodeObject {

    private static let ourTypeTag = UUID()

    public final func setWrappedValue<T>(_ wrap: T?, forKey key: NodeWrappedDataKey<T>) throws {
        let env = base.environment
        let id = ObjectIdentifier(key)
        let raw = try base.rawValue()
        if try hasTypeTag(Self.ourTypeTag) {
            var objRaw: UnsafeMutableRawPointer!
            try env.check(napi_unwrap(env.raw, raw, &objRaw))
            let objUnmanaged = Unmanaged<WrappedData>.fromOpaque(objRaw)
            let obj = objUnmanaged.takeUnretainedValue()
            obj.value[id] = key
            // remove the wrapper if the dict is now empty
            if obj.value.isEmpty {
                try env.check(napi_remove_wrap(env.raw, raw, nil))
                objUnmanaged.release()
            }
        } else if let wrap = wrap {
            let obj = WrappedData([:])
            obj.value[id] = wrap
            let objUnmanaged = Unmanaged<WrappedData>.passRetained(obj)
            let objRaw = objUnmanaged.toOpaque()
            do {
                try env.check(napi_wrap(env.raw, raw, objRaw, cWrapFinalizer, nil, nil))
            } catch {
                objUnmanaged.release()
                throw error
            }
            try setTypeTag(Self.ourTypeTag)
        }
    }

    public final func wrappedValue<T>(forKey key: NodeWrappedDataKey<T>) throws -> T? {
        guard try hasTypeTag(Self.ourTypeTag) else { return nil }
        let env = base.environment
        var objRaw: UnsafeMutableRawPointer!
        try env.check(napi_unwrap(env.raw, base.rawValue(), &objRaw))
        let obj = Unmanaged<WrappedData>.fromOpaque(objRaw).takeUnretainedValue()
        return obj.value[ObjectIdentifier(key)] as? T
    }

}

#endif

// MARK: - Finalizers

private typealias FinalizeWrapper = Box<(NodeContext) throws -> Void>

private func cFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer!) {
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        try Unmanaged<FinalizeWrapper>
            .fromOpaque(data)
            .takeRetainedValue() // releases the wrapper post-call
            .value(ctx)
    }
}

extension NodeObject {

    // Wrap should be sufficient in most cases, but finalizers are handy
    // when you don't want to tag the object
    public final func addFinalizer(_ finalizer: @escaping (NodeContext) throws -> Void) throws {
        let data = Unmanaged.passRetained(FinalizeWrapper(finalizer)).toOpaque()
        try base.environment.check(
            napi_add_finalizer(base.environment.raw, base.rawValue(), data, cFinalizer, nil, nil)
        )
    }

}

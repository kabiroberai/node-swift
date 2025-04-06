internal import CNodeAPI
import Foundation

public class NodeObject: NodeValue, NodeObjectConvertible, NodeLookupable {

    @_spi(NodeAPI) public final let base: NodeValueBase
    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        self.base = base
    }

    class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let type = try value.nodeType()
        return type == .object || type == .function
    }

    public init(coercing value: NodeValueConvertible) throws {
        let val = try value.nodeValue()
        // just a fast path for performance
        if let val = val as? NodeObject {
            self.base = val.base
            return
        }
        let ctx = NodeContext.current
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(napi_coerce_to_object(env.raw, val.rawValue(), &coerced))
        self.base = NodeValueBase(raw: coerced, in: ctx)
    }

    public init(_ properties: NodeObjectPropertyList = [:]) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var obj: napi_value!
        try env.check(napi_create_object(env.raw, &obj))
        base = NodeValueBase(raw: obj, in: ctx)
        try define(properties)
    }

    public final func isInstance(of constructor: NodeFunction) throws -> Bool {
        var result = false
        try base.environment.check(
            napi_instanceof(base.environment.raw, base.rawValue(), constructor.base.rawValue(), &result)
        )
        return result
    }

}

extension Dictionary: NodeValueConvertible, NodeObjectConvertible, NodePropertyConvertible
    where Key == String, Value == NodePropertyConvertible {
    public func nodeValue() throws -> NodeValue {
        try NodeObject(.init(Array(self)))
    }
}

extension Dictionary: NodeValueCreatable, AnyNodeValueCreatable where Key == String, Value == NodeValue {
    public static func from(_ value: NodeObject) throws -> [Key: Value] {
        guard let keys = try value.propertyNames(
            collectionMode: .includePrototypes,
            filter: [.enumerable, .skipSymbols],
            conversion: .numbersToStrings
        ).as([NodeValue].self) else {
            throw NodeAPIError(.invalidArg, message: "Could not convert JS object to [NodeValue]")
        }
        return try Dictionary(uniqueKeysWithValues: keys.map {
            guard let k = try $0.as(String.self) else {
                throw NodeAPIError(.invalidArg, message: "Expected string key in JS object, got \($0)")
            }
            return try (k, value[k].nodeValue())
        })
    }
}

// MARK: - Properties

extension NodeObject {

    @NodeActor public final class DynamicProperty: NodeValueConvertible, NodeCallable, NodeLookupable {
        let obj: NodeObject
        let key: NodeValueConvertible

        @_spi(NodeAPI) public var receiver: NodeValueConvertible { obj }

        init(obj: NodeObject, key: NodeValueConvertible) {
            self.obj = obj
            self.key = key
        }

        public func nodeValue() throws -> NodeValue {
            let env = obj.base.environment
            var ret: napi_value!
            try env.check(
                napi_get_property(
                    env.raw,
                    obj.base.rawValue(),
                    key.rawValue(),
                    &ret
                )
            )
            return AnyNodeValue(raw: ret)
        }

        public func set(to value: NodeValueConvertible) throws {
            let env = obj.base.environment
            try env.check(napi_set_property(
                env.raw,
                obj.base.rawValue(),
                key.rawValue(),
                value.rawValue()
            ))
        }

        @discardableResult
        public func delete() throws -> Bool {
            let env = obj.base.environment
            var result = false
            try env.check(napi_delete_property(
                env.raw,
                obj.base.rawValue(),
                key.rawValue(),
                &result
            ))
            return result
        }

        public func exists() throws -> Bool {
            let env = obj.base.environment
            var result = false
            try env.check(napi_has_property(
                env.raw,
                obj.base.rawValue(),
                key.rawValue(),
                &result
            ))
            return result
        }

        public func property(forKey key: NodeValueConvertible) throws -> DynamicProperty {
            // forwards to nodeValue()
            guard let obj = try self.as(NodeObject.self) else {
                throw NodeAPIError(.objectExpected, message: "Cannot access property on non-object")
            }
            return DynamicProperty(obj: obj, key: key)
        }
    }

    public final func property(forKey key: NodeValueConvertible) -> DynamicProperty {
        DynamicProperty(obj: self, key: key)
    }

    public final func hasOwnProperty(_ key: NodeName) throws -> Bool {
        var result = false
        let env = base.environment
        try env.check(napi_has_own_property(
            env.raw,
            base.rawValue(),
            key.rawValue(),
            &result
        ))
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

    public struct KeyFilter: RawRepresentable, OptionSet, Sendable {
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
        conversion: KeyConversion
    ) throws -> NodeArray {
        let env = base.environment
        var result: napi_value!
        try env.check(
            napi_get_all_property_names(
                env.raw,
                base.rawValue(),
                collectionMode.raw,
                filter.raw,
                conversion.raw,
                &result
            )
        )
        return NodeArray(NodeValueBase(raw: result, in: .current))
    }

    public final func define(_ properties: NodeObjectPropertyList) throws {
        let env = base.environment
        var descriptors: [napi_property_descriptor] = []
        var callbacks: [NodePropertyBase.Callbacks] = []
        for (name, prop) in properties.elements {
            let (desc, cb) = try prop.nodeProperty.raw(name: name)
            descriptors.append(desc)
            if let cb = cb {
                callbacks.append(cb)
            }
        }
        try env.check(napi_define_properties(env.raw, base.rawValue(), properties.elements.count, descriptors))
        if !callbacks.isEmpty {
            // retain new callbacks
            try addFinalizer { _ = callbacks }
        }
    }

    public final func prototype() throws -> AnyNodeValue {
        let env = base.environment
        var result: napi_value!
        try env.check(napi_get_prototype(env.raw, base.rawValue(), &result))
        return AnyNodeValue(raw: result)
    }

    public final func freeze() throws {
        #if !NAPI_VERSIONED || NAPI_GE_8
        try base.environment.check(
            napi_object_freeze(
                base.environment.raw,
                base.rawValue()
            )
        )
        #else
        try Node.Object.freeze(self)
        #endif
    }

    public final func seal() throws {
        #if !NAPI_VERSIONED || NAPI_GE_8
        try base.environment.check(
            napi_object_seal(
                base.environment.raw,
                base.rawValue()
            )
        )
        #else
        try Node.Object.seal(self)
        #endif
    }

}

public final class NodeWrappedDataKey<T> {
    public init() {}
}

extension NodeObject {

    // WeakMap<any, external<Extra>>
    @NodeInstanceData private static var objectMap: NodeObject?

    private func getObjectMap() throws -> NodeObject {
        if let map = Self.objectMap { return map }
        let map = try Node.WeakMap.new()
        Self.objectMap = map
        return map
    }

    @NodeActor final class Extra {
        var wrappedValues: [ObjectIdentifier: Any] = [:]
    }

    func extra() throws -> Extra {
        let objectMap = try getObjectMap()

        if let external = try objectMap.get(self).as(NodeExternal.self) {
            return try external.value() as! Extra
        }

        let extra = Extra()
        let external = try NodeExternal(value: extra)
        try objectMap.set(self, external)
        return extra
    }

}

extension NodeObject {

    final func setWrappedValue(_ wrap: Any?, forID id: ObjectIdentifier) throws {
        try extra().wrappedValues[id] = wrap
    }

    final func wrappedValue(forID id: ObjectIdentifier) throws -> Any? {
        try extra().wrappedValues[id]
    }

    public final func setWrappedValue<T>(_ wrap: T?, forKey key: NodeWrappedDataKey<T>) throws {
        try setWrappedValue(wrap, forID: ObjectIdentifier(key))
    }

    public final func wrappedValue<T>(forKey key: NodeWrappedDataKey<T>) throws -> T? {
        try wrappedValue(forID: ObjectIdentifier(key)) as? T
    }

}

// MARK: - Finalizers

private typealias FinalizeWrapper = Box<() -> Void>

extension NodeObject {

    // Wrap should be sufficient in most cases, but finalizers are handy
    // when you don't want to tag the object
    public final func addFinalizer(_ finalizer: @escaping () -> Void) throws {
        let data = Unmanaged.passRetained(FinalizeWrapper(finalizer)).toOpaque()
        try base.environment.check(
            napi_add_finalizer(base.environment.raw, base.rawValue(), data, { rawEnv, data, hint in
                Unmanaged<FinalizeWrapper>
                    .fromOpaque(data!)
                    .takeRetainedValue() // releases the wrapper post-call
                    .value()
            }, nil, nil)
        )
    }

}

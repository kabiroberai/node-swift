import CNodeAPI
import Foundation

@dynamicMemberLookup
public final class NodeObject: NodeValue, NodeObjectConvertible {

    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        self.base = base
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

}

extension Dictionary: NodeValueConvertible, NodeObjectConvertible where Key == String, Value: NodeValueConvertible {
    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        let obj = try NodeObject(in: ctx)
        // TODO: Use defineOwnProperties?
        for (key, value) in self {
            try obj[key].set(to: value)
        }
        return obj
    }
}

// MARK: - Properties

extension NodeObject {

    @dynamicMemberLookup
    public class DynamicProperty {
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
            return NodeValueBase(raw: ret, in: ctx).as(AnyNodeValue.self)
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
        public func delete(key: NodeValueConvertible) throws -> Bool {
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
            try get(in: ctx)
                .as(NodeFunction.self)
                .call(in: ctx, receiver: resolveObject(ctx), arguments: args)
        }

        public func property(forKey key: NodeValueConvertible) -> DynamicProperty {
            DynamicProperty(environment: environment, key: key) {
                try self.get(in: $0).as(NodeObject.self)
            }
        }

        public subscript(key: NodeValueConvertible) -> DynamicProperty {
            property(forKey: key)
        }

        public subscript(dynamicMember key: String) -> DynamicProperty {
            property(forKey: key)
        }
    }

    public func property(forKey key: NodeValueConvertible) -> DynamicProperty {
        DynamicProperty(environment: base.environment, key: key) { _ in self }
    }

    public subscript(key: NodeValueConvertible) -> DynamicProperty {
        property(forKey: key)
    }

    public subscript(dynamicMember key: String) -> DynamicProperty {
        property(forKey: key)
    }

    public func hasOwnProperty(_ key: NodeName) throws -> Bool {
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

    public func freeze() throws {
        try base.environment.check(
            napi_object_freeze(
                base.environment.raw,
                base.rawValue()
            )
        )
    }

    public func seal() throws {
        try base.environment.check(
            napi_object_seal(
                base.environment.raw,
                base.rawValue()
            )
        )
    }

}

// MARK: - Wrap

public class NodeWrappedDataKey<T> {
    public init() {}
}

private typealias WrappedData = Box<[ObjectIdentifier: Any]>

private func cFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer!) {
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

    public func setWrappedValue<T>(_ wrap: T?, forKey key: NodeWrappedDataKey<T>) throws {
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
                try env.check(napi_wrap(env.raw, raw, objRaw, cFinalizer, nil, nil))
            } catch {
                objUnmanaged.release()
                throw error
            }
            try setTypeTag(Self.ourTypeTag)
        }
    }

    public func wrappedValue<T>(forKey key: NodeWrappedDataKey<T>) throws -> T? {
        guard try hasTypeTag(Self.ourTypeTag) else { return nil }
        let env = base.environment
        var objRaw: UnsafeMutableRawPointer!
        try env.check(napi_unwrap(env.raw, base.rawValue(), &objRaw))
        let obj = Unmanaged<WrappedData>.fromOpaque(objRaw).takeUnretainedValue()
        return obj.value[ObjectIdentifier(key)] as? T
    }

    // NOTE: We choose not to expose the finalizer features since everything it does
    // is replicated by our wrappedValue implementation (users can use deinitializers
    // in their wrapped values to determine when an object is finalized)

}

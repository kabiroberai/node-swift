import CNodeAPI
import Foundation

@dynamicMemberLookup
public final class NodeObject: NodeValueStorage {

    public var storedValue: NodeValue
    public init(_ value: NodeValue) {
        self.storedValue = value
    }

    public init(coercing value: NodeValueConvertible, in ctx: NodeContext) throws {
        let env = ctx.environment
        var coerced: napi_value!
        try env.check(napi_coerce_to_object(env.raw, value.nodeValue(in: ctx).rawValue(), &coerced))
        self.storedValue = NodeValue(raw: coerced, in: ctx)
    }

    public init(newObjectIn ctx: NodeContext) throws {
        let env = ctx.environment
        var obj: napi_value!
        try env.check(napi_create_object(env.raw, &obj))
        storedValue = NodeValue(raw: obj, in: ctx)
    }

}

extension Dictionary: NodeValueLiteral, NodeValueConvertible where Key == String, Value: NodeValueConvertible {
    func storage(in ctx: NodeContext) throws -> NodeObject {
        let obj = try NodeObject(newObjectIn: ctx)
        // TODO: Use defineOwnProperties?
        for (key, value) in self {
            try obj[key].set(to: value)
        }
        return obj
    }
}

// MARK: - Properties

extension NodeObject {

    public class DynamicProperty {
        public let object: NodeObject
        public let key: NodeValueConvertible

        init(object: NodeObject, key: NodeValueConvertible) {
            self.object = object
            self.key = key
        }

        public func get(in ctx: NodeContext) throws -> NodeValue {
            var ret: napi_value!
            try ctx.environment.check(
                napi_get_property(
                    ctx.environment.raw,
                    object.storedValue.rawValue(),
                    key.nodeValue(in: ctx).rawValue(),
                    &ret
                )
            )
            return NodeValue(raw: ret, in: ctx)
        }

        public func set(to value: NodeValueConvertible) throws {
            try NodeContext.withUnmanagedContext(environment: object.storedValue.environment) { ctx in
                _ = try ctx.environment.check(napi_set_property(
                    ctx.environment.raw,
                    object.storedValue.rawValue(),
                    key.nodeValue(in: ctx).rawValue(),
                    value.nodeValue(in: ctx).rawValue()
                ))
            }
        }

        @discardableResult
        public func delete(key: NodeValueConvertible) throws -> Bool {
            var result = false
            try NodeContext.withUnmanagedContext(environment: object.storedValue.environment) { ctx in
                try ctx.environment.check(napi_delete_property(
                    ctx.environment.raw,
                    object.storedValue.rawValue(),
                    key.nodeValue(in: ctx).rawValue(),
                    &result
                ))
            }
            return result
        }

        public func exists() throws -> Bool {
            var result = false
            try NodeContext.withUnmanagedContext(environment: object.storedValue.environment) { ctx in
                try ctx.environment.check(napi_has_property(
                    ctx.environment.raw,
                    object.storedValue.rawValue(),
                    key.nodeValue(in: ctx).rawValue(),
                    &result
                ))
            }
            return result
        }

        @discardableResult
        public func callAsFunction(in ctx: NodeContext, _ args: NodeValueConvertible...) throws -> NodeValue {
            try NodeFunction(get(in: ctx), in: ctx)
                .call(in: ctx, receiver: object, args: args)
        }
    }

    public func property(forKey key: NodeValueConvertible) -> DynamicProperty {
        DynamicProperty(object: self, key: key)
    }

    public subscript(key: NodeValueConvertible) -> DynamicProperty {
        property(forKey: key)
    }

    public subscript(dynamicMember key: String) -> DynamicProperty {
        property(forKey: key)
    }

    public func hasOwnProperty(_ key: NodeName) throws -> Bool {
        var result = false
        try NodeContext.withUnmanagedContext(environment: storedValue.environment) { ctx in
            try ctx.environment.check(napi_has_own_property(
                ctx.environment.raw,
                storedValue.rawValue(),
                key.nodeValue(in: ctx).rawValue(),
                &result
            ))
        }
        return result
    }

    public func freeze() throws {
        try storedValue.environment.check(
            napi_object_freeze(
                storedValue.environment.raw,
                storedValue.rawValue()
            )
        )
    }

    public func seal() throws {
        try storedValue.environment.check(
            napi_object_seal(
                storedValue.environment.raw,
                storedValue.rawValue()
            )
        )
    }

}

// MARK: - Type Tags

extension NodeObject {

    private func withTypeTag<T>(_ tag: UUID, do action: (UnsafePointer<napi_type_tag>) throws -> T) rethrows -> T {
        try withUnsafePointer(to: tag.uuid) {
            try $0.withMemoryRebound(to: napi_type_tag.self, capacity: 1, action)
        }
    }

    // can be called at most once per value
    public func setTypeTag(_ tag: UUID) throws {
        let env = storedValue.environment
        try withTypeTag(tag) {
            try env.check(
                napi_type_tag_object(
                    env.raw, storedValue.rawValue(), $0
                )
            )
        }
    }

    public func hasTypeTag(_ tag: UUID) throws -> Bool {
        let env = storedValue.environment
        var result = false
        try withTypeTag(tag) {
            try env.check(
                napi_check_object_type_tag(
                    env.raw, storedValue.rawValue(), $0, &result
                )
            )
        }
        return result
    }

}

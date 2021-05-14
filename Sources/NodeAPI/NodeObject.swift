import CNodeAPI
import Foundation

public final class NodeObject: NodeValueStorage {

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in ctx: NodeContext) throws {
        self.storedValue = try value.nodeValue(in: ctx)
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
        // TODO: Implement
        fatalError("TODO: Support dictionary literals")
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

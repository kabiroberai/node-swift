import CNodeAPI
import Foundation

public final class NodeObject: NodeValueStorage {

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in env: NodeEnvironment) throws {
        // TODO: Do we really need this?
        let nodeVal = try value.nodeValue(in: env)
        let object = try env.run(script: "Object")
        guard try nodeVal.isInstance(of: object, in: env) else {
            throw NodeError(.objectExpected)
        }
        self.storedValue = nodeVal
    }

    public init(coercing value: NodeValueConvertible, in env: NodeEnvironment) throws {
        var coerced: napi_value!
        try env.check(napi_coerce_to_object(env.raw, value.nodeValue(in: env).rawValue(in: env), &coerced))
        self.storedValue = NodeValue(raw: coerced, in: env)
    }

    public init(newObjectIn env: NodeEnvironment) throws {
        var obj: napi_value!
        try env.check(napi_create_object(env.raw, &obj))
        storedValue = NodeValue(raw: obj, in: env)
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
    public func setTypeTag(_ tag: UUID, in env: NodeEnvironment) throws {
        try withTypeTag(tag) {
            try env.check(
                napi_type_tag_object(
                    env.raw, storedValue.rawValue(in: env), $0
                )
            )
        }
    }

    public func hasTypeTag(_ tag: UUID, in env: NodeEnvironment) throws -> Bool {
        var result = false
        try withTypeTag(tag) {
            try env.check(
                napi_check_object_type_tag(
                    env.raw, storedValue.rawValue(in: env), $0, &result
                )
            )
        }
        return result
    }

}

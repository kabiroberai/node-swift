import CNodeAPI

public final class NodeArray: NodeObject {

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_array(env.raw, value.rawValue(), &result))
        return result
    }

    // capacity is the initial capacity; the array can still grow
    public init(capacity: Int? = nil) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        if let length = capacity {
            try env.check(napi_create_array_with_length(env.raw, length, &result))
        } else {
            try env.check(napi_create_array(env.raw, &result))
        }
        super.init(NodeValueBase(raw: result, in: ctx))
    }

    public func count() throws -> Int {
        let env = base.environment
        var length: UInt32 = 0
        try env.check(napi_get_array_length(env.raw, base.rawValue(), &length))
        return Int(length)
    }

}

extension Array: NodeValueConvertible, NodeObjectConvertible, NodePropertyConvertible
    where Element == NodeValueConvertible {
    public func nodeValue() throws -> NodeValue {
        let arr = try NodeArray(capacity: count)
        for (idx, element) in enumerated() {
            try arr[Double(idx)].set(to: element)
        }
        return arr
    }
}

extension Array: NodeValueCreatable where Element == NodeValue {
    public init(_ value: NodeArray) throws {
        self = try (0..<value.count()).map { try value[Double($0)].get() }
    }
}

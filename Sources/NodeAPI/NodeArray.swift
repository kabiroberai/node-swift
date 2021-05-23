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

    public init(initialCapacity: Int? = nil, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        if let length = initialCapacity {
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

extension Array: NodeValueConvertible, NodeObjectConvertible where Element: NodeValueConvertible {
    public func nodeValue(in ctx: NodeContext) throws -> NodeValue {
        let arr = try NodeArray(initialCapacity: count, in: ctx)
        for (idx, element) in enumerated() {
            try arr[Double(idx)].set(to: element)
        }
        return arr
    }
}

import CNodeAPI

public final class NodeSymbol: NodeValueStorage {

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in ctx: NodeContext) throws {
        self.storedValue = try value.nodeValue(in: ctx)
    }

    public init(description: String? = nil, in ctx: NodeContext) throws {
        let env = ctx.environment
        var result: napi_value!
        let descRaw = try description.map {
            try NodeString($0, in: ctx).nodeValue(in: ctx).rawValue()
        }
        try env.check(napi_create_symbol(env.raw, descRaw, &result))
        self.storedValue = NodeValue(raw: result, in: ctx)
    }

}

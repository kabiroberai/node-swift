import CNodeAPI

public final class NodeSymbol: NodeValueStorage, NodeName {

    public enum SymbolError: Error {
        case invalidSymbol
    }

    public var storedValue: NodeValue
    public init(_ value: NodeValue) {
        self.storedValue = value
    }

    public init(newSymbolIn ctx: NodeContext, description: String? = nil) throws {
        let env = ctx.environment
        var result: napi_value!
        let descRaw = try description.map {
            try NodeString($0, in: ctx).nodeValue(in: ctx).rawValue()
        }
        try env.check(napi_create_symbol(env.raw, descRaw, &result))
        self.storedValue = NodeValue(raw: result, in: ctx)
    }

    public static func wellKnown(_ name: String, in ctx: NodeContext) throws -> NodeSymbol {
        let symbol = try NodeObject(ctx.global().Symbol.get(in: ctx))
        let val = try symbol[name].get(in: ctx)
        guard try val.type() == .symbol else {
            throw SymbolError.invalidSymbol
        }
        return NodeSymbol(val)
    }

}

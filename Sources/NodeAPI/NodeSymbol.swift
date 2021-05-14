import CNodeAPI

public final class NodeSymbol: NodeValueStorage {

    public enum SymbolError: Error {
        case symbolExpected
    }

    public let storedValue: NodeValue
    public init(_ value: NodeValueConvertible, in env: NodeEnvironment) throws {
        let nodeValue = try value.nodeValue(in: env)
        guard try nodeValue.type(in: env) == .symbol else {
            throw SymbolError.symbolExpected
        }
        self.storedValue = nodeValue
    }

    public init(description: String? = nil, in env: NodeEnvironment) throws {
        var result: napi_value!
        let descRaw = try description.map {
            try NodeString($0, in: env).nodeValue(in: env).rawValue(in: env)
        }
        try env.check(napi_create_symbol(env.raw, descRaw, &result))
        self.storedValue = NodeValue(raw: result, in: env)
    }

}

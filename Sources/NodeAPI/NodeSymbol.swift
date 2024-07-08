@_implementationOnly import CNodeAPI

public final class NodeSymbol: NodePrimitive, NodeName {
    @_spi(NodeAPI) public let base: NodeValueBase
    @_spi(NodeAPI) public init(_ base: NodeValueBase) {
        self.base = base
    }
  
    public static func global(for name: String) throws -> NodeSymbol {
        let ctx = NodeContext.current
        let env = ctx.environment
        let symbol = try env.global.Symbol.for(name)
        if let nonNullSymbol = try symbol.nodeValue().as(NodeSymbol.self) {
            return nonNullSymbol
        } else {
            throw NodeAPIError(.genericFailure, message: "globalThis.Symbol.for('\(name)') is not a symbol")
        }
    }

    public static func deferredGlobal(for name: String) -> NodeDeferredName {
        NodeDeferredName { try global(for: name) }
    }
  
    public static func wellKnown(propertyName name: String) throws -> NodeSymbol {
        let ctx = NodeContext.current
        let env = ctx.environment
        let property = try env.global.Symbol[name].as(NodeSymbol.self)
        if let property = property {
            return property
        } else {
            throw NodeAPIError(.genericFailure, message: "globalThis.Symbol.\(name) is not a symbol")
        }
    }

    public static func deferredWellKnown(propertyName name: String) -> NodeDeferredName {
        NodeDeferredName { try wellKnown(propertyName: name) }
    }

    public init(description: String? = nil) throws {
        let ctx = NodeContext.current
        let env = ctx.environment
        var result: napi_value!
        let descRaw = try description.map { try $0.rawValue() }
        try env.check(napi_create_symbol(env.raw, descRaw, &result))
        self.base = NodeValueBase(raw: result, in: ctx)
    }
}

extension NodeSymbol {
    /// Allows implementing the Iterable protocol for an object.
    /// This method is called by the `for-of` statement or destructuring like `[...obj]`.
    public static var iterator: NodeDeferredName { deferredWellKnown(propertyName: "iterator") }

    /// This symbol allows customizing how NodeJS formats objects in console.log.
    /// See https://nodejs.org/api/util.html#custom-inspection-functions-on-objects
    public static var utilInspectCustom: NodeDeferredName { deferredGlobal(for: "nodejs.util.inspect.custom")}
}
@NodeActor public struct NodeModuleRegistrar {
    private let env: OpaquePointer?
    public init(_ env: OpaquePointer?) {
        self.env = env
    }
    // NB: these should match the #NodeModule signatures for the macro to forward properly
    public func register(init create: @escaping @NodeActor () throws -> NodeValueConvertible) -> OpaquePointer? {
        NodeContext.withContext(environment: NodeEnvironment(env!)) { _ in
            try create().rawValue()
        }
    }
    public func register(exports create: @autoclosure @escaping @NodeActor () throws -> NodeValueConvertible) -> OpaquePointer? {
        register(init: create)
    }
}

@freestanding(declaration)
public macro NodeModule(init: @escaping @NodeActor () throws -> NodeValueConvertible)
    = #externalMacro(module: "NodeAPIMacros", type: "NodeModuleMacro")

@freestanding(declaration)
public macro NodeModule(exports: @autoclosure @escaping @NodeActor () throws -> NodeValueConvertible)
    = #externalMacro(module: "NodeAPIMacros", type: "NodeModuleMacro")

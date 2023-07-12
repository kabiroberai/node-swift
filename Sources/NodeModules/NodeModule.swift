import NodeAPI

@_documentation(visibility: private)
@NodeActor public func _registerModule(
    _ env: OpaquePointer?,
    _ create: @escaping @NodeActor () throws -> NodeValueConvertible
) -> OpaquePointer? {
    moduleEntrypoint(env, create)
}

@freestanding(declaration)
public macro NodeModule(init: @escaping @NodeActor () throws -> NodeValueConvertible)
    = #externalMacro(module: "NodeModulesMacros", type: "NodeModuleMacro")

@freestanding(declaration)
public macro NodeModule(exports: NodeValueConvertible)
    = #externalMacro(module: "NodeModulesMacros", type: "NodeModuleMacro")

@_implementationOnly import CNodeAPI
import Foundation

@NodeActor public func _registerModule(
    _ env: OpaquePointer?,
    _ create: @escaping @NodeActor () throws -> NodeValueConvertible
) -> OpaquePointer? {
    NodeContext.withContext(environment: NodeEnvironment(env!)) { _ in
        try create().rawValue()
    }
}

@freestanding(declaration)
public macro NodeModule(init: @escaping @NodeActor () throws -> NodeValueConvertible)
    = #externalMacro(module: "NodeAPIMacros", type: "NodeModuleMacro")

@freestanding(declaration)
public macro NodeModule(exports: NodeValueConvertible)
    = #externalMacro(module: "NodeAPIMacros", type: "NodeModuleMacro")

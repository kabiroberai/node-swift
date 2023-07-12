import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

struct NodeModuleMacro: DeclarationMacro {
    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let swiftName = context.makeUniqueName("register")

        let ctor: ExprSyntax
        if let trailing = node.trailingClosure {
            ctor = ExprSyntax(trailing)
        } else if let argument = node.argumentList.first {
            if argument.label?.text == "exports" {
                // the Result.get silences warnings if the expr doesn't throw
                ctor = "{ try (\(argument.expression), Swift.Result {}.get()).0 }"
            } else {
                ctor = argument.expression
            }
        } else {
            throw MacroError(description: "Expected initialization expression in #NodeModule")
        }

        return ["""
        @_cdecl("node_swift_register")
        @NodeAPI.NodeActor(unsafe)
        public func \(swiftName)(env: Swift.OpaquePointer) -> Swift.OpaquePointer? {
            NodeModules._registerModule(env, \(ctor))
        }
        """]
    }
}

struct MacroError: Error, CustomStringConvertible {
    let description: String
}

@main struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        NodeModuleMacro.self,
    ]
}

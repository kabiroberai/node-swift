import SwiftSyntax
import SwiftSyntaxMacros

struct NodeMethodMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            context.diagnose(.init(node: Syntax(declaration), message: .expectedFunction))
            return []
        }

        // we don't need to change the attribtues for static methods
        // because the NodeMethod.init overloads that accept non-instance
        // methods automatically union the attributes with `.static`.
        let attributes = node.nodeAttributes ?? ".defaultMethod"
        let sig = function.signature

        let val: ExprSyntax = if function.modifiers.hasKeyword(.static) {
            "_NodeSelf.\(function.name) as \(sig.functionType)"
        } else {
            "{ $0.\(function.name) } as (_NodeSelf) -> \(sig.functionType)"
        }

        return ["""
        @NodeActor static let $\(function.name)
            = NodeMethod(attributes: \(attributes), \(val))
        """]
    }
}

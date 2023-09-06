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

        let attributes = node.nodeAttributes ?? ".defaultMethod"
        let sig = function.signature

        let type: TypeSyntax = if function.modifiers.hasKeyword(.static) {
            "\(sig.functionType)"
        } else {
            "(_NodeSelf) -> \(sig.functionType)"
        }

        return ["""
        @NodeActor static let $\(function.name)
            = NodeMethod(attributes: \(attributes), _NodeSelf.\(function.name)\(sig.arguments) as \(type))
        """]
    }
}

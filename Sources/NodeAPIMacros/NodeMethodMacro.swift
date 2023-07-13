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

        return ["""
        @NodeActor private static let $\(function.identifier) = NodeMethod(attributes: \(attributes), _NodeSelf.\(function.identifier)\(sig.arguments) as (_NodeSelf) -> \(sig.functionType))
        """]
    }
}

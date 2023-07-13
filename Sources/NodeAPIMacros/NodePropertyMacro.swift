import SwiftSyntax
import SwiftSyntaxMacros

struct NodePropertyMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let identifier = declaration.as(VariableDeclSyntax.self)?.identifier else {
            context.diagnose(.init(node: Syntax(declaration), message: .expectedProperty))
            return []
        }

        let attributes = node.nodeAttributes ?? ".defaultProperty"

        return ["""
        @NodeActor private static let $\(identifier) = \
            NodeComputedProperty(attributes: \(attributes), \\_NodeSelf.\(identifier))
        """]
    }
}

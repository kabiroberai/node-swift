import SwiftSyntax
import SwiftSyntaxMacros

struct NodePropertyMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let identifier = declaration.as(VariableDeclSyntax.self)?.identifier?.trimmed else {
            context.diagnose(.init(node: Syntax(declaration), message: .expectedProperty))
            return []
        }

        let attributes = node.nodeAttributes ?? ".defaultProperty"

        let raw = identifier.textWithoutBackticks
        return ["""
        @NodeActor static let $\(raw: raw)
            = NodeProperty(attributes: \(attributes), \\_NodeSelf.\(identifier))
        """]
    }
}

import SwiftSyntax
import SwiftSyntaxMacros

struct NodeNameMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let _ = node.nodeAttributes else {
            context.diagnose(.init(node: Syntax(node), message: .expectedName))
            return []
        }

        // Processed by NodeClassMacro.
        return []
    }
}

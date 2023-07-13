import SwiftSyntax
import SwiftSyntaxMacros

struct NodeConstructorMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let ctor = declaration.as(InitializerDeclSyntax.self) else {
            context.diagnose(.init(node: Syntax(declaration), message: .expectedInit))
            return []
        }

        var sig = ctor.signature
        sig.output = .init(returnType: "_NodeSelf" as TypeSyntax)

        return ["""
        @NodeActor static let construct = NodeConstructor(_NodeSelf.init\(sig.arguments) as \(sig.functionType))
        """]
    }
}

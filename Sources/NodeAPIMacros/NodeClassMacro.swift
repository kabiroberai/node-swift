import SwiftSyntax
import SwiftSyntaxMacros

struct NodeClassMacro: ExtensionMacro {
    static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(.init(node: Syntax(declaration), message: .expectedClassDecl))
            return []
        }

        guard classDecl.modifiers.hasKeyword(.final) else {
            context.diagnose(.init(node: Syntax(declaration), message: .expectedFinal))
            return []
        }

        let dict = DictionaryExprSyntax {
            for member in classDecl.memberBlock.members {
                let identifier =
                    if let function = member.decl.as(FunctionDeclSyntax.self),
                       function.attributes.hasAttribute(named: "NodeMethod") == true {
                        function.name
                    } else if let property = member.decl.as(VariableDeclSyntax.self),
                              property.attributes.hasAttribute(named: "NodeProperty") == true {
                        property.identifier
                    } else {
                        nil as TokenSyntax?
                    }
                
                if let identifier = identifier?.trimmed {
                    let key = member.decl.attributes?.findAttribute(named: "NodeName")?.nodeAttributes ?? "\(literal: identifier.text)" as ExprSyntax
                    DictionaryElementSyntax(
                        key: key,
                        value: "$\(identifier)" as ExprSyntax
                    )
                }
            }
        }

        let inheritanceClause = protocols.isEmpty ? nil : InheritanceClauseSyntax(
            inheritedTypes: .init(protocols.map { .init(type: $0) })
        )

        return [ExtensionDeclSyntax(extendedType: type, inheritanceClause: inheritanceClause) {
            DeclSyntax("""
            @NodeActor public static let properties: NodeClassPropertyList = \(dict)
            """)
        }]
    }
}

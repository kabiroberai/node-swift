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

        guard classDecl.modifiers?.hasKeyword(.final) == true else {
            context.diagnose(.init(node: Syntax(declaration), message: .expectedFinal))
            return []
        }

        let dict = DictionaryExprSyntax {
            for member in classDecl.memberBlock.members {
                let identifier =
                    if let function = member.decl.as(FunctionDeclSyntax.self),
                       function.attributes?.hasAttribute(named: "NodeMethod") == true {
                        function.identifier
                    } else if let property = member.decl.as(VariableDeclSyntax.self),
                              property.attributes?.hasAttribute(named: "NodeProperty") == true {
                        property.identifier
                    } else {
                        nil as TokenSyntax?
                    }
                if let identifier {
                    DictionaryElementSyntax(
                        keyExpression: "\(literal: identifier.text)" as ExprSyntax,
                        valueExpression: "$\(identifier)" as ExprSyntax
                    )
                }
            }
        }

        let inheritanceClause = protocols.isEmpty ? nil : TypeInheritanceClauseSyntax(
            inheritedTypeCollection: .init(protocols.map { .init(typeName: $0) })
        )

        return [ExtensionDeclSyntax(extendedType: type, inheritanceClause: inheritanceClause) {
            DeclSyntax("""
            @NodeActor public static let properties: NodeClassPropertyList = \(dict)
            """)
        }]
    }
}

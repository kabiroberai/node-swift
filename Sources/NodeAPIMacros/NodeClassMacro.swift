import SwiftSyntax
import SwiftSyntaxMacros

struct NodeClassMacro: ConformanceMacro, MemberMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingConformancesOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [(TypeSyntax, GenericWhereClauseSyntax?)] {
        [("NodeClass", nil)]
    }

    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
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

        return ["""
        @NodeActor static let properties: NodeClassPropertyList = \(dict)
        """]
    }
}

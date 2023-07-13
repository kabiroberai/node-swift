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

        guard let mods = classDecl.modifiers, mods.lazy.map(\.name.tokenKind).contains(.keyword(.final)) else {
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

extension AttributeListSyntax {
    fileprivate func hasAttribute(named name: String) -> Bool {
        contains {
            if case let .attribute(value) = $0 {
                value.attributeName.as(SimpleTypeIdentifierSyntax.self)?.name.text == name
            } else {
                false
            }
        }
    }
}

extension AttributeSyntax {
    var nodeAttributes: ExprSyntax? {
        if case .argumentList(let tuple) = argument, let elt = tuple.first {
            elt.expression
        } else {
            nil
        }
    }
}

extension FunctionSignatureSyntax {
    var functionType: FunctionTypeSyntax {
        FunctionTypeSyntax(
            arguments: TupleTypeElementListSyntax(input.parameterList.map { .init(type: $0.type) }),
            effectSpecifiers: .init(
                asyncSpecifier: effectSpecifiers?.asyncSpecifier,
                throwsSpecifier: effectSpecifiers?.throwsSpecifier
            ),
            output: .init(returnType: output?.returnType.trimmed ?? "Void")
        )
    }

    var arguments: DeclNameArgumentsSyntax {
        if input.parameterList.isEmpty {
            DeclNameArgumentsSyntax(leftParen: .unknown(""), arguments: [], rightParen: .unknown(""))
        } else {
            DeclNameArgumentsSyntax(arguments: .init(input.parameterList.map { .init(name: $0.firstName.trimmed) }))
        }
    }
}

extension VariableDeclSyntax {
    var identifier: TokenSyntax? {
        guard bindings.count == 1 else { return nil }
        return bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier
    }
}

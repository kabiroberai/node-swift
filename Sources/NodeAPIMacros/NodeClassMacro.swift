import SwiftSyntax
import SwiftSyntaxMacros

struct NodeClassMacro: ConformanceMacro, MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingConformancesOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [(TypeSyntax, GenericWhereClauseSyntax?)] {
        [("NodeClass", nil)]
    }

    public static func expansion(
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

        let className = classDecl.identifier.trimmed

        let dict = DictionaryExprSyntax {
            for member in classDecl.memberBlock.members {
                if let function = member.decl.as(FunctionDeclSyntax.self),
                   let attribute = function.attributes?.attribute(named: "NodeMethod") {
                    let attributes = attribute.nodeAttributes ?? ".defaultMethod"
                    let sig = function.signature
                    DictionaryElementSyntax(
                        keyExpression: "\(literal: function.identifier.text)" as ExprSyntax,
                        valueExpression: """
                        NodeMethod(attributes: \(attributes), \(className).\(function.identifier)\(sig.arguments) as (\(className)) -> \(sig.functionType))
                        """ as ExprSyntax
                    )
                } else if let property = member.decl.as(VariableDeclSyntax.self),
                          let attribute = property.attributes?.attribute(named: "NodeComputedProperty") {
                    let attributes = attribute.nodeAttributes ?? ".defaultProperty"
                    for binding in property.bindings {
                        if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                            DictionaryElementSyntax(
                                keyExpression: "\(literal: pattern.identifier.text)" as ExprSyntax,
                                valueExpression: """
                                NodeComputedProperty(attributes: \(attributes), \\\(className).\(pattern.identifier))
                                """ as ExprSyntax
                            )
                        }
                    }
                }
            }
        }

        var decls: [DeclSyntax] = ["""
        @NodeActor static let properties: NodeClassPropertyList = \(dict)
        """]

        let constructors = classDecl.memberBlock.members
            .compactMap { $0.decl.as(InitializerDeclSyntax.self) }
            .filter { $0.attributes?.attribute(named: "NodeConstructor") != nil }

        switch constructors.count {
        case 0:
            break
        case 1:
            var sig = constructors[0].signature
            sig.output = .init(returnType: "\(className)" as TypeSyntax)
            decls.append("""
            @NodeActor static let construct = NodeConstructor(\(className).init\(sig.arguments) as \(sig.functionType))
            """)
        default:
            context.diagnose(.init(node: Syntax(constructors[1]), message: .tooManyConstructors))
        }

        return decls
    }
}

extension AttributeListSyntax {
    fileprivate func attribute(named name: String) -> AttributeSyntax? {
        lazy.compactMap(\.attribute).first {
            $0.attributeName.as(SimpleTypeIdentifierSyntax.self)?.name.text == name
        }
    }
}

extension AttributeListSyntax.Element {
    fileprivate var attribute: AttributeSyntax? {
        switch self {
        case .attribute(let attributeSyntax):
            return attributeSyntax
        case .ifConfigDecl:
            return nil
        }
    }
}

extension AttributeSyntax {
    fileprivate var nodeAttributes: ExprSyntax? {
        if case .argumentList(let tuple) = argument, let elt = tuple.first {
            elt.expression
        } else {
            nil
        }
    }
}

extension FunctionSignatureSyntax {
    fileprivate var functionType: FunctionTypeSyntax {
        FunctionTypeSyntax(
            arguments: TupleTypeElementListSyntax(input.parameterList.map { .init(type: $0.type) }),
            effectSpecifiers: .init(
                asyncSpecifier: effectSpecifiers?.asyncSpecifier,
                throwsSpecifier: effectSpecifiers?.throwsSpecifier
            ),
            output: .init(returnType: output?.returnType.trimmed ?? "Void")
        )
    }

    fileprivate var arguments: DeclNameArgumentsSyntax {
        DeclNameArgumentsSyntax(arguments: .init(input.parameterList.map { .init(name: $0.firstName.trimmed) }))
    }
}

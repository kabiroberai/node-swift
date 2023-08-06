import SwiftSyntax

extension AttributeListSyntax {
    func hasAttribute(named name: String) -> Bool {
        contains {
            if case let .attribute(value) = $0 {
                value.attributeName.as(SimpleTypeIdentifierSyntax.self)?.name.trimmed.text == name
            } else {
                false
            }
        }
    }
}

extension ModifierListSyntax {
    func hasKeyword(_ keyword: Keyword) -> Bool {
        lazy.map(\.name.tokenKind).contains(.keyword(keyword))
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
            arguments: TupleTypeElementListSyntax {
                for parameter in input.parameterList {
                    TupleTypeElementSyntax(type: parameter.type, trailingComma: parameter.trailingComma)
                }
            },
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

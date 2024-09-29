import SwiftSyntax

extension AttributeListSyntax {
    func hasAttribute(named name: String) -> Bool {
        contains {
            if case let .attribute(value) = $0 {
                value.attributeName.as(IdentifierTypeSyntax.self)?.name.trimmed.text == name
            } else {
                false
            }
        }
    }
}

extension DeclModifierListSyntax {
    func hasKeyword(_ keyword: Keyword) -> Bool {
        lazy.map(\.name.tokenKind).contains(.keyword(keyword))
    }
}

extension AttributeSyntax {
    var nodeAttributes: ExprSyntax? {
        if case .argumentList(let tuple) = arguments, let elt = tuple.first {
            elt.expression
        } else {
            nil
        }
    }
}

extension FunctionSignatureSyntax {
    var functionType: FunctionTypeSyntax {
        FunctionTypeSyntax(
            parameters: TupleTypeElementListSyntax {
                for parameter in parameterClause.parameters {
                    TupleTypeElementSyntax(type: parameter.type, trailingComma: parameter.trailingComma)
                }
            },
            effectSpecifiers: effectSpecifiers?.typeEffectSpecifiers,
            returnClause: .init(type: returnClause?.type.trimmed ?? "Void")
        )
    }

    var arguments: DeclNameArgumentsSyntax {
        if parameterClause.parameters.isEmpty {
            DeclNameArgumentsSyntax(leftParen: .unknown(""), arguments: [], rightParen: .unknown(""))
        } else {
            DeclNameArgumentsSyntax(arguments: .init(parameterClause.parameters.map { .init(name: $0.firstName.trimmed) }))
        }
    }
}

extension FunctionEffectSpecifiersSyntax {
    var typeEffectSpecifiers: TypeEffectSpecifiersSyntax {
        #if canImport(SwiftSyntax600)
        TypeEffectSpecifiersSyntax(
            asyncSpecifier: asyncSpecifier,
            throwsClause: throwsClause
        )
        #else
        TypeEffectSpecifiersSyntax(
            asyncSpecifier: asyncSpecifier,
            throwsSpecifier: throwsSpecifier
        )
        #endif
    }
}

extension VariableDeclSyntax {
    var identifier: TokenSyntax? {
        guard bindings.count == 1 else { return nil }
        return bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier
    }
}

extension TokenSyntax {
    var textWithoutBackticks: String {
        var text = text
        if text.hasPrefix("`") && text.hasSuffix("`") {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }
}

#if !canImport(SwiftSyntax510)
extension FreestandingMacroExpansionSyntax {
    var arguments: LabeledExprListSyntax {
        argumentList
    }
}
#endif

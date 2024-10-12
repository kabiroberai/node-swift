import SwiftSyntax
import SwiftSyntaxMacros

struct NodeModuleMacro: DeclarationMacro {
    // we avoid formatting to preserve sourceLocation info
    static var formatMode: FormatMode { .disabled }

    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let name = context.makeUniqueName("register")

        let call: CodeBlockItemSyntax
        if node.arguments.count == 1,
           let argument = node.arguments.first,
           argument.label?.text == "exports" {
            // wrap `exports:` argument in a closure to allow for NodeActor isolation.
            // https://github.com/kabiroberai/node-swift/issues/26
            call = "NodeAPI.NodeModuleRegistrar(env).register { \(argument.expression) }"
        } else {
            call = CodeBlockItemSyntax(item: .expr(ExprSyntax(FunctionCallExprSyntax(
                calledExpression: "NodeAPI.NodeModuleRegistrar(env).register" as ExprSyntax,
                leftParen: node.leftParen,
                arguments: node.arguments,
                rightParen: node.rightParen,
                trailingClosure: node.trailingClosure,
                additionalTrailingClosures: node.additionalTrailingClosures
            ))))
        }

        let start = context.location(of: node, at: .afterLeadingTrivia, filePathMode: .filePath)!
        var file = start.file
        #if os(Windows)
        // on Windows, the literal will use raw string syntax by default:
        // along the lines of #"C:\Users\..."#. But sourceLocation doesn't
        // like this, so extract the underlying string and re-encode it
        // as an escaped string instead: "C:\\Users\\..."
        if let literal = file.as(StringLiteralExprSyntax.self),
           literal.openingPounds != nil,
           let raw = literal.representedLiteralValue {
            file = "\"\(raw: raw.replacing("\\", with: "\\\\"))\""
        }
        #endif

        return ["""
        @_cdecl("node_swift_register")
        public func \(name)(env: Swift.OpaquePointer) -> Swift.OpaquePointer? {
            #sourceLocation(file: \(file), line: \(start.line))
        \(call)
            #sourceLocation()
        }
        """]
    }
}

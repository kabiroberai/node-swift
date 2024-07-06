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

        return ["""
        @_cdecl("node_swift_register")
        public func \(name)(env: Swift.OpaquePointer) -> Swift.OpaquePointer? {
            #sourceLocation(file: \(start.file), line: \(start.line))
        \(call)
            #sourceLocation()
        }
        """]
    }
}

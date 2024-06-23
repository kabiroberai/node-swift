import SwiftSyntax
import SwiftSyntaxMacros

struct NodeModuleMacro: DeclarationMacro {
    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let name = context.makeUniqueName("register")

        let call = FunctionCallExprSyntax(
            calledExpression: "NodeAPI.NodeModuleRegistrar(env).register" as ExprSyntax,
            leftParen: node.leftParen,
            arguments: node.arguments,
            rightParen: node.rightParen,
            trailingClosure: node.trailingClosure,
            additionalTrailingClosures: node.additionalTrailingClosures
        )

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

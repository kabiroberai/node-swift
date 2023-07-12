import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        NodeClassMacro.self,
        NodeMarkerMacro.self,
    ]
}

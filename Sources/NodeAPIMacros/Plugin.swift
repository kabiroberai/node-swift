import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main struct NodeAPIMacros: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        NodeClassMacro.self,
        NodeModuleMacro.self,
        NodeMarkerMacro.self,
    ]
}

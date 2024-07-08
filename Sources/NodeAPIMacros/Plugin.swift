import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        NodeMethodMacro.self,
        NodePropertyMacro.self,
        NodeConstructorMacro.self,
        NodeClassMacro.self,
        NodeModuleMacro.self,
        NodeNameMacro.self,
    ]
}

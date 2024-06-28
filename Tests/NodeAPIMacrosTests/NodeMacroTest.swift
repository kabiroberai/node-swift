@testable import NodeAPIMacros
import SwiftSyntaxMacros
import MacroTesting
import XCTest

typealias NodeMacroTest = NodeMacroTestBase & NodeMacroTestProtocol

extension [String: any Macro.Type] {
    static let node: Self = [
        "NodeMethod": NodeMethodMacro.self,
        "NodeProperty": NodePropertyMacro.self,
        "NodeConstructor": NodeConstructorMacro.self,
        "NodeClass": NodeClassMacro.self,
        "NodeModule": NodeModuleMacro.self,
    ]
}

class NodeMacroTestBase: XCTestCase {
    override func invokeTest() {
        withMacroTesting(
            isRecording: (self as? NodeMacroTestProtocol)?.isRecording,
            macros: .node
        ) {
            super.invokeTest()
        }
    }
}

protocol NodeMacroTestProtocol {
    var isRecording: Bool { get }
}

extension NodeMacroTestProtocol {
    var isRecording: Bool { false }
}

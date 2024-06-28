import MacroTesting
import XCTest

final class NodePropertyMacroTests: NodeMacroTest {
    func testBasic() {
        assertMacro {
            #"""
            @NodeProperty let x = 5
            """#
        } expansion: {
            #"""
            let x = 5

            @NodeActor static let $x
                = NodeProperty(attributes: .defaultProperty, \_NodeSelf.x)
            """#
        }
    }

    func testVar() {
        assertMacro {
            #"""
            @NodeProperty var x = 5
            """#
        } expansion: {
            #"""
            var x = 5

            @NodeActor static let $x
                = NodeProperty(attributes: .defaultProperty, \_NodeSelf.x)
            """#
        }
    }

    func testParens() {
        assertMacro {
            #"""
            @NodeProperty() let x = 5
            """#
        } expansion: {
            #"""
            let x = 5

            @NodeActor static let $x
                = NodeProperty(attributes: .defaultProperty, \_NodeSelf.x)
            """#
        }
    }

    func testAttributes() {
        assertMacro {
            #"""
            @NodeProperty(.enumerable) let x = 5
            """#
        } expansion: {
            #"""
            let x = 5

            @NodeActor static let $x
                = NodeProperty(attributes: .enumerable, \_NodeSelf.x)
            """#
        }
    }

    func testNonProperty() {
        assertMacro {
            #"""
            @NodeProperty(.enumerable) func foo() {}
            """#
        } diagnostics: {
            """
            @NodeProperty(.enumerable) func foo() {}
            ┬───────────────────────────────────────
            ╰─ 🛑 @NodeProperty can only be applied to a property
            """
        }
    }
}

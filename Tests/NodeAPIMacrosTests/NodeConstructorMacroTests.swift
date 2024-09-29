import MacroTesting
import XCTest

final class NodeConstructorMacroTests: NodeMacroTest {
    func testBasic() {
        assertMacro {
            #"""
            @NodeConstructor init() {}
            """#
        } expansion: {
            """
            init() {}

            @NodeActor public static let construct
                = NodeConstructor(_NodeSelf.init as @NodeActor () -> _NodeSelf)
            """
        }
    }

    func testNonConstructor() {
        assertMacro {
            #"""
            @NodeConstructor func foo() {}
            """#
        } diagnostics: {
            """
            @NodeConstructor func foo() {}
            ┬─────────────────────────────
            ╰─ 🛑 @NodeConstructor can only be applied to an initializer
            """
        }
    }

    func testEffectful() {
        assertMacro {
            #"""
            @NodeConstructor init() async throws {}
            """#
        } expansion: {
            """
            init() async throws {}

            @NodeActor public static let construct
                = NodeConstructor(_NodeSelf.init as @NodeActor () async throws -> _NodeSelf)
            """
        }
    }

    func testArguments() {
        assertMacro {
            #"""
            @NodeConstructor init(_ x: Int, y: String) {
                print("hi")
            }
            """#
        } expansion: {
            """
            init(_ x: Int, y: String) {
                print("hi")
            }

            @NodeActor public static let construct
                = NodeConstructor(_NodeSelf.init(_:y:) as @NodeActor (Int, String) -> _NodeSelf)
            """
        }
    }
}

import MacroTesting
import XCTest

final class NodeMethodMacrosTests: NodeMacroTest {
    func testBasicMethod() {
        assertMacro {
            """
            @NodeMethod
            func foo() {}
            """
        } expansion: {
            """
            func foo() {}

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor () -> Void)
            """
        }
    }

    func testNonMethod() {
        assertMacro {
            """
            @NodeMethod
            let foo = 5
            """
        } diagnostics: {
            """
            @NodeMethod
            ╰─ 🛑 @NodeMethod can only be applied to a function
            let foo = 5
            """
        }
    }

    func testBasicMethodInline() {
        assertMacro {
            """
            @NodeMethod func foo() {
                print("hi")
            }
            """
        } expansion: {
            """
            func foo() {
                print("hi")
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor () -> Void)
            """
        }
    }

    func testMethodAttributes() {
        assertMacro {
            """
            @NodeMethod(.writable)
            func foo() {
                print("hi")
            }
            """
        } expansion: {
            """
            func foo() {
                print("hi")
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .writable, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor () -> Void)
            """
        }
    }

    func testMethodNoAttributes() {
        assertMacro {
            """
            @NodeMethod()
            func foo() {
                print("hi")
            }
            """
        } expansion: {
            """
            func foo() {
                print("hi")
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor () -> Void)
            """
        }
    }

    func testMethodEffects() {
        assertMacro {
            """
            @NodeMethod
            func foo() async throws {
                print("hi")
            }
            """
        } expansion: {
            """
            func foo() async throws {
                print("hi")
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor () async throws -> Void)
            """
        }
    }

    func testTypedThrows() throws {
        assertMacro {
            """
            @NodeMethod
            func foo() throws(CancellationError) {
                throw CancellationError()
            }
            """
        } expansion: {
            """
            func foo() throws(CancellationError) {
                throw CancellationError()
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor () throws(CancellationError) -> Void)
            """
        }
    }

    func testMethodReturn() {
        assertMacro {
            """
            @NodeMethod
            func foo() throws -> String {
                return "abc"
            }
            """
        } expansion: {
            """
            func foo() throws -> String {
                return "abc"
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor () throws -> String)
            """
        }
    }

    func testMethodArgs() {
        assertMacro {
            #"""
            @NodeMethod
            func foo(x: Int) async -> String {
                return "\(x)"
            }
            """#
        } expansion: {
            #"""
            func foo(x: Int) async -> String {
                return "\(x)"
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor (Int) async -> String)
            """#
        }
    }

    func testMethodManyArgs() {
        assertMacro {
            #"""
            @NodeMethod
            func foo(x: Int, _ y: Double) throws {
                return "\(x)"
            }
            """#
        } expansion: {
            #"""
            func foo(x: Int, _ y: Double) throws {
                return "\(x)"
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, {
                    $0.foo
                } as (_NodeSelf) -> @NodeActor (Int, Double) throws -> Void)
            """#
        }
    }

    func testStaticMethod() {
        assertMacro {
            #"""
            @NodeMethod
            static func foo(x: Int) throws -> String {
                return "\(x)"
            }
            """#
        } expansion: {
            #"""
            static func foo(x: Int) throws -> String {
                return "\(x)"
            }

            @NodeActor static let $foo
                = NodeMethod(attributes: .defaultMethod, _NodeSelf.foo as @NodeActor (Int) throws -> String)
            """#
        }
    }
}

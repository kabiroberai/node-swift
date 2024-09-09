@testable import NodeAPIMacros
import MacroTesting
import XCTest

final class NodeClassMacroTests: XCTestCase {
    override func invokeTest() {
        withMacroTesting(
            isRecording: false,
            macros: ["NodeClass": NodeClassMacro.self]
        ) {
            super.invokeTest()
        }
    }

    func testEmpty() {
        assertMacro {
            #"""
            @NodeClass final class Foo {
            }
            """#
        } expansion: {
            """
            final class Foo {
            }

            extension Foo {
                @NodeActor public static let properties: NodeClassPropertyList = [:]
            }
            """
        }
    }

    func testBasic() {
        assertMacro {
            #"""
            @NodeClass final class Foo {
                @NodeProperty var x = 5
                @NodeProperty var y = 6
                var z = 7

                @NodeMethod func foo() {}
                func bar() {}
                @NodeMethod func baz() {}
            }
            """#
        } expansion: {
            """
            final class Foo {
                @NodeProperty var x = 5
                @NodeProperty var y = 6
                var z = 7

                @NodeMethod func foo() {}
                func bar() {}
                @NodeMethod func baz() {}
            }

            extension Foo {
                @NodeActor public static let properties: NodeClassPropertyList = ["x": $x, "y": $y, "foo": $foo, "baz": $baz]
            }
            """
        }
    }

    func testCustomName() {
        assertMacro {
            #"""
            @NodeClass final class Foo {
                @NodeName("q")
                @NodeProperty var x = 5
                @NodeName(NodeSymbol.someGlobalSymbol)
                @NodeProperty var y = 6
                var z = 7

                @NodeMethod func foo() {}
                func bar() {}
                @NodeMethod func baz() {}
            }
            """#
        } expansion: {
            """
            final class Foo {
                @NodeName("q")
                @NodeProperty var x = 5
                @NodeName(NodeSymbol.someGlobalSymbol)
                @NodeProperty var y = 6
                var z = 7

                @NodeMethod func foo() {}
                func bar() {}
                @NodeMethod func baz() {}
            }

            extension Foo {
                @NodeActor public static let properties: NodeClassPropertyList = ["q": $x, NodeSymbol.someGlobalSymbol: $y, "foo": $foo, "baz": $baz]
            }
            """
        }
    }

    func testNonClass() {
        assertMacro {
            #"""
            @NodeClass struct Foo {}
            """#
        } diagnostics: {
            """
            @NodeClass struct Foo {}
            ┬───────────────────────
            ╰─ 🛑 @NodeClass can only be applied to a class
            """
        }
    }

    func testNonFinal() {
        assertMacro {
            #"""
            @NodeClass class Foo {}
            """#
        } diagnostics: {
            """
            @NodeClass class Foo {}
            ┬──────────────────────
            ╰─ 🛑 @NodeClass classes must be final
            """
        }
    }

    func testIntegration() {
        assertMacro(.node) {
            #"""
            @NodeClass final class Foo {
                @NodeProperty var x = 5
                @NodeProperty(.enumerable) var y = "hello"
                var z = 7

                @NodeName("longerFooName")
                @NodeMethod func foo(_ x: String) async throws {
                    throw SomeError(x)
                }

                func bar() {}

                @NodeMethod func baz(returnNumber: Bool) async throws -> any NodeValueConvertible {
                    try await Task.sleep(for: .seconds(2))
                    return returnNumber ? 5 : "hi"
                }

                @NodeConstructor init(x: Int) throws {
                    self.x = x
                }
            }
            """#
        } expansion: {
            #"""
            final class Foo {
                var x = 5

                @NodeActor static let $x
                    = NodeProperty(attributes: .defaultProperty, \_NodeSelf.x)
                var y = "hello"

                @NodeActor static let $y
                    = NodeProperty(attributes: .enumerable, \_NodeSelf.y)
                var z = 7

                @NodeName("longerFooName")
                func foo(_ x: String) async throws {
                    throw SomeError(x)
                }

                @NodeActor static let $foo
                    = NodeMethod(attributes: .defaultMethod, {
                        $0.foo
                    } as (_NodeSelf) -> (String) async throws -> Void)

                func bar() {}

                func baz(returnNumber: Bool) async throws -> any NodeValueConvertible {
                    try await Task.sleep(for: .seconds(2))
                    return returnNumber ? 5 : "hi"
                }

                @NodeActor static let $baz
                    = NodeMethod(attributes: .defaultMethod, {
                        $0.baz
                    } as (_NodeSelf) -> (Bool) async throws -> any NodeValueConvertible)

                init(x: Int) throws {
                    self.x = x
                }

                @NodeActor public static let construct
                    = NodeConstructor(_NodeSelf.init(x:) as (Int) throws -> _NodeSelf)
            }

            extension Foo {
                @NodeActor public static let properties: NodeClassPropertyList = ["x": $x, "y": $y, "longerFooName": $foo, "baz": $baz]
            }
            """#
        }
    }
}

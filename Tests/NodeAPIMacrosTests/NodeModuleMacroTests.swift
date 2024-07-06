import MacroTesting
import XCTest

final class NodeModuleMacrosTests: NodeMacroTest {
    func testClosure() {
        assertMacro {
            """
            #NodeModule {
                return 0
            }
            """
        } expansion: {
            """
            @_cdecl("node_swift_register")
            public func __macro_local_8registerfMu_(env: Swift.OpaquePointer) -> Swift.OpaquePointer? {
                #sourceLocation(file: "Test.swift", line: 1)
            NodeAPI.NodeModuleRegistrar(env).register{
                return 0
            }
                #sourceLocation()
            }
            """
        }
    }

    func testClosureExplicit() {
        assertMacro {
            """
            #NodeModule(init: {
                return 0
            })
            """
        } expansion: {
            """
            @_cdecl("node_swift_register")
            public func __macro_local_8registerfMu_(env: Swift.OpaquePointer) -> Swift.OpaquePointer? {
                #sourceLocation(file: "Test.swift", line: 1)
            NodeAPI.NodeModuleRegistrar(env).register(init: {
                return 0
            })
                #sourceLocation()
            }
            """
        }
    }

    func testExports() {
        // This MUST be rewritten to a closure because autoclosures appear to use
        // caller isolation instead of callee isolation as of Swift 5.10. This means
        // anything that requires @NodeActor isolation would otherwise fail.
        //
        // See: https://github.com/kabiroberai/node-swift/issues/26
        assertMacro {
            """
            #NodeModule(exports: ["foo": 1])
            """
        } expansion: {
            """
            @_cdecl("node_swift_register")
            public func __macro_local_8registerfMu_(env: Swift.OpaquePointer) -> Swift.OpaquePointer? {
                #sourceLocation(file: "Test.swift", line: 1)
            NodeAPI.NodeModuleRegistrar(env).register { ["foo": 1] }
                #sourceLocation()
            }
            """
        }
    }
}

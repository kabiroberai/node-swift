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

    func testExports() {
        assertMacro {
            """
            #NodeModule(exports: ["foo": 1])
            """
        } expansion: {
            """
            @_cdecl("node_swift_register")
            public func __macro_local_8registerfMu_(env: Swift.OpaquePointer) -> Swift.OpaquePointer? {
                #sourceLocation(file: "Test.swift", line: 1)
            NodeAPI.NodeModuleRegistrar(env).register(exports: ["foo": 1])
                #sourceLocation()
            }
            """
        }
    }
}

import NodeAPI
import NodeJSC
import XCTest
import JavaScriptCore

final class NodeJSCTests: XCTestCase {
    private var sut: JSContext!

    override func invokeTest() {
        var ran = false
        sut = JSContext()!
        addTeardownBlock { 
            self.sut = nil
        }
        NodeEnvironment.withJSC(context: sut) {
            super.invokeTest()
            ran = true
        }
        XCTAssert(ran)
    }

    @NodeActor func testBasic() async throws {
        let string = try NodeString("Hello, world!")
        XCTAssertEqual(try string.string(), "Hello, world!")
    }

    @NodeActor func testGC() async throws {
        var finalized = false
        try autoreleasepool {
            let obj = try NodeObject()
            try obj.addFinalizer {
                finalized = true
            }
        }
        sut.debugGC()
        XCTAssert(finalized)

        finalized = false
        let obj = try NodeObject()
        try obj.addFinalizer {
            finalized = true
        }
        sut.debugGC()
        _ = finalized
        XCTAssertFalse(finalized)
    }

    @NodeActor func testNodeClassGC() async throws {
        var finalized1 = false
        var finalized2 = false
        try autoreleasepool {
            let obj1 = MyClass { finalized1 = true }
            let obj2 = MyClass { finalized2 = true }
            try Node.global.stored1.set(to: obj1)
            try Node.global.stored2.set(to: obj2)
            try Node.global.stored2.set(to: NodeNull())
        }
        sut.debugGC()
        XCTAssertFalse(finalized1)
        XCTAssertTrue(finalized2)
    }
}

@NodeClass final class MyClass {
    let onDeinit: () -> Void
    init(onDeinit: @escaping () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit { onDeinit() }
}

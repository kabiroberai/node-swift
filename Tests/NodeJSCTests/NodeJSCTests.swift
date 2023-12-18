@testable import NodeAPI
import NodeJSC
import XCTest
import JavaScriptCore

final class NodeJSCTests: XCTestCase {
    private var sut: JSContext!

    override func invokeTest() {
        var ran = false
        sut = JSContext()!
        NodeEnvironment.withJSC(context: sut) {
            super.invokeTest()
            ran = true
        }
        self.sut = nil
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
        await sut.debugGC()
        XCTAssert(finalized)

        finalized = false
        let obj = try NodeObject()
        try obj.addFinalizer {
            finalized = true
        }
        await sut.debugGC()
        _ = finalized
        XCTAssertFalse(finalized)
    }

    @NodeActor func testTypeTag() async throws {
        let tag1 = UUID()
        let tag2 = UUID()
        let object = try NodeObject()
        XCTAssertEqual(try object.hasTypeTag(tag1), .absent)
        try object.setTypeTag(tag1)
        XCTAssertEqual(try object.hasTypeTag(tag1), .present)
        XCTAssertEqual(try object.hasTypeTag(tag2), .absent)

        var threw = false
        do {
            try object.setTypeTag(tag2)
        } catch {
            threw = true
            let nodeError = try XCTUnwrap(error as? NodeAPIError)
            XCTAssertEqual(nodeError.code, .invalidArg)
        }
        XCTAssert(threw)
    }

    @NodeActor func testWrappedValue() async throws {
        let key1 = NodeWrappedDataKey<String>()
        let key2 = NodeWrappedDataKey<Int>()
        let object = try NodeObject()
        XCTAssertNil(try object.wrappedValue(forKey: key1))
        try object.setWrappedValue("One", forKey: key1)
        try object.setWrappedValue(2, forKey: key2)
        XCTAssertEqual(try object.wrappedValue(forKey: key1), "One")
        XCTAssertEqual(try object.wrappedValue(forKey: key2), 2)
    }

    @NodeActor func testNodeClassGC() async throws {
        var finalized1 = false
        var finalized2 = false
        try autoreleasepool {
            let obj1 = MyClass { finalized1 = true }
            let obj2 = MyClass { finalized2 = true }
            try Node.global.stored1.set(to: obj1)
            try Node.global.stored2.set(to: obj2)
            try Node.global.stored2.set(to: null)
        }
        await sut.debugGC()
        XCTAssertFalse(finalized1)
        XCTAssertTrue(finalized2)
    }

    @NodeActor func testPromise() async throws {
        try Node.tick.set(to: NodeFunction { _ in
            await Task.yield()
        })
        let obj = try Node.run(script: """
        (async () => {
            await tick()
            return 123
        })()
        """)
        let value = try await obj.as(NodePromise.self)?.value.as(NodeNumber.self)?.double()
        XCTAssertEqual(value, 123)
    }

    @NodeActor func testThrowing() async throws {
        var threw = false
        do {
            try Node.run(script: "blah")
        } catch {
            threw = true
            let unwrapped = try XCTUnwrap((error as? AnyNodeValue)?.as(NodeError.self))
            let name = try unwrapped.name.as(String.self)
            XCTAssertEqual(name, "ReferenceError")
            let message = try unwrapped.message.as(String.self)
            XCTAssertEqual(message, "Can't find variable: blah")
        }
        XCTAssert(threw, "Expected script to throw")
    }

    @NodeActor func testPropertyNames() async throws {
        let object = try NodeObject()
        try object.foo.set(to: "bar")

        let names = try XCTUnwrap(object.propertyNames(
            collectionMode: .includePrototypes,
            filter: .allProperties,
            conversion: .numbersToStrings
        ).as([String].self))
        XCTAssert(Set(["constructor", "__proto__", "toString", "foo"]).subtracting(names).isEmpty)

        let ownNames = try XCTUnwrap(object.propertyNames(
            collectionMode: .ownOnly,
            filter: .allProperties,
            conversion: .numbersToStrings
        ).as([String].self))
        XCTAssertEqual(ownNames, ["foo"])
    }
}

@NodeClass final class MyClass {
    let onDeinit: () -> Void
    init(onDeinit: @escaping () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit { onDeinit() }
}

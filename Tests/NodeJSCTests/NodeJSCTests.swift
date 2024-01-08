@testable import NodeAPI
import NodeJSC
import XCTest
import JavaScriptCore

@NodeActor final class NodeJSCTests: XCTestCase {
    private let sutBox = Box<JSContext?>(nil)
    private nonisolated var sut: JSContext { sutBox.value! }

    nonisolated override func invokeTest() {
        var global: JSManagedValue?
        autoreleasepool {
            guard let sut = JSContext() else { fatalError("Could not create JSContext") }
            sutBox.value = sut
            global = JSManagedValue(value: sut.globalObject)
            var queue: NodeAsyncQueue.Handle?
            NodeEnvironment.withJSC(context: sut) {
                queue = try NodeAsyncQueue(label: "queue").handle()
            }
            guard let queue else { fatalError("Could not obtain NodeAsyncQueue") }
            NodeActor.$target.withValue(queue) {
                super.invokeTest()
            }
            self.sutBox.value = nil
            sut.debugGCSync()
        }
        if let global {
            // TODO: call napi_env_jsc_delete when the time is right
            // we might want to use refs as the source of truth
            // instead of relying on a unique owner
            _ = global
            // XCTAssertNil(global.value)
        } else {
            XCTFail("global == nil")
        }
    }

    func testBasic() async throws {
        let string = try NodeString("Hello, world!")
        XCTAssertEqual(try string.string(), "Hello, world!")
    }

    func testGC() async throws {
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

    func testWrappedValue() async throws {
        let key1 = NodeWrappedDataKey<String>()
        let key2 = NodeWrappedDataKey<Int>()
        let object = try NodeObject()
        XCTAssertNil(try object.wrappedValue(forKey: key1))
        try object.setWrappedValue("One", forKey: key1)
        try object.setWrappedValue(2, forKey: key2)
        XCTAssertEqual(try object.wrappedValue(forKey: key1), "One")
        XCTAssertEqual(try object.wrappedValue(forKey: key2), 2)
    }

    func testWrappedValueDeinit() async throws {
        weak var value: NSObject?
        var objectRef: NodeObject?
        try autoreleasepool {
            let object = try NodeObject()
            let key = NodeWrappedDataKey<NSObject>()
            let obj = NSObject()
            value = obj
            try object.setWrappedValue(obj, forKey: key)
            objectRef = object
        }
        await sut.debugGC()
        XCTAssertNotNil(value)
        _ = objectRef
        objectRef = nil
        await sut.debugGC()
        await sut.debugGC()
        XCTAssertNil(value)
    }

    func testNodeClassGC() async throws {
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

    func testPromise() async throws {
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

    func testThrowing() async throws {
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

    func testPropertyNames() async throws {
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

import NodeAPI
import Foundation

final class CleanupHandler: Sendable {
    let global: NodeObject
    init(global: NodeObject) {
        self.global = global
    }
    deinit {
        print("Cleanup!")
    }

    @NodeInstanceData static var shared: CleanupHandler?
}

#NodeModule {
    let captured = try NodeString("hi")

    try Node.setTimeout(NodeFunction {
        print("Called our timeout! Captured: \(captured)")
        return undefined
    }, 1000)

    let res = try Node.run(script: "[1, 15]").as(NodeArray.self)!
    print("Count: \(try res.count())")
    print("Num: \(try res[1].nodeValue())")

    print("Symbol.iterator is a \(try Node.Symbol.iterator.nodeType())")

    let strObj = try Node.run(script: "('hello')")
    print("'\(strObj)' is a \(try strObj.nodeType())")

    let doStuff = try NodeFunction(name: "doStuff") { args in
        print("Called! Arg 0 type: \(try args.first?.nodeType() as Any)")
        return 5
    }
    let exports = doStuff
    try doStuff("hello", 15)

    let key = NodeWrappedDataKey<String>()
    let obj = try NodeObject()
    try obj.setWrappedValue("hello", forKey: key)
    print("wrapped value: \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")
    try obj.setWrappedValue(nil, forKey: key)
    print("wrapped value (shouldn't be found): \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")

    try withExtendedLifetime(Node.global) {
        print("First copy of global: \($0)")
    }

    CleanupHandler.shared = CleanupHandler(global: try Node.global)

    Task {
        try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
        try print(Node.run(script: "1+1"))
    }

    let promise = try NodePromise {
        try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
        return 5
    }

    Task {
        print("PROMISE: \(try await promise.value)")
    }

    return exports
}

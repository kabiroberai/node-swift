import NodeAPI
import Foundation

// to unwrap the existential
private extension NodeValue {
    func type() -> NodeValue.Type {
        Self.self
    }
}

@main struct NativeStuff: NodeModule {

    var exports: NodeValueConvertible

    init() throws {
        let env = NodeEnvironment.current

        let captured = try NodeString("hi")
        try env.global().setTimeout(NodeFunction { _ in
            print("Called our timeout! Captured: \(captured)")
            return try NodeUndefined()
        }, 1000)

        let res = try env.run(script: "[1, 15]").as(NodeArray.self)!
        print("Count: \(try res.count())")
        let num = try res[1].get().as(NodeNumber.self)!
        print("Num: \(num)")

        print("Symbol.iterator is a \(try env.global().Symbol.iterator.get().type())")

        let strObj = try env.run(script: "('hello')")
        print("'\(strObj)' is a \(strObj.type())")

        let doStuff = try NodeFunction(name: "doStuff") { info in
            print("Called! Arg 0 type: \(info.arguments.first?.type() as Any)")
            return 5
        }
        exports = doStuff
        try doStuff("hello", 15)

        let key = NodeWrappedDataKey<String>()
        let obj = try NodeObject()
        try obj.setWrappedValue("hello", forKey: key)
        print("wrapped value: \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")
        try obj.setWrappedValue(nil, forKey: key)
        print("wrapped value (shouldn't be found): \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")

        try withExtendedLifetime(env.global()) {
            print("First copy of global: \($0)")
        }

        class CleanupHandler {
            let global: NodeObject
            init(global: NodeObject) {
                self.global = global
            }
            deinit {
                print("Cleanup!")
            }
        }
        let global = try env.global()
        let cleanupHandler = CleanupHandler(global: global)

        try env.setInstanceData(cleanupHandler, for: .init())

        let q = try NodeAsyncQueue(label: "DISPATCH_CB")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            try? q.async {
                print("dispatch callback")
            }
        }
    }

}

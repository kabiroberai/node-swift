import NodeAPI
import Foundation

@main struct NativeStuff: NodeModule {

    var exports: NodeValueConvertible

    init() throws {
        let captured = try NodeString("hi")

        try Node.setTimeout(NodeFunction {
            print("Called our timeout! Captured: \(captured)")
            return Node.undefined
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
        exports = doStuff
        try doStuff("hello", 15)

        let key = NodeWrappedDataKey<String>()
        let obj = try NodeObject()
        try obj.setWrappedValue("hello", forKey: key)
        print("wrapped value: \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")
        try obj.setWrappedValue(nil, forKey: key)
        print("wrapped value (shouldn't be found): \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")

        try withExtendedLifetime(Node.global()) {
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
        let global = try Node.global()
        let cleanupHandler = CleanupHandler(global: global)

        try Node.setInstanceData(cleanupHandler, for: .init())

        let q = try NodeAsyncQueue(label: "DISPATCH_CB")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            try? q.async {
                print("dispatch callback")
            }
        }
    }

}

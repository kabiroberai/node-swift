import NodeAPI
import Foundation

@main struct NativeStuff: NodeModule {

    var exports: NodeValueConvertible

    init(context: NodeContext) throws {
        let captured = try NodeString("hi", in: context)
        try context.global().setTimeout(in: context, NodeFunction(in: context) { ctx, _ in
            print("Called our timeout! Captured: \(captured)")
            return try ctx.undefined()
        }, 1000)

        let res = try context.run(script: "[1, 15]").as(NodeObject.self)
        let num = try res[1].get(in: context).as(NodeNumber.self)
        print("Num: \(num)")

        print("Symbol.iterator is a \(try context.global().Symbol.iterator.get(in: context).type())")

        let strObj = try context.run(script: "('hello')")
        print("'\(strObj)' is a \(try strObj.type())")

        let doStuff = try NodeFunction(name: "doStuff", in: context) { ctx, info in
            print("Called! Arg 0: \(try info.arguments.first?.type() ?? .undefined)")
            return 5
        }
        exports = doStuff
        try doStuff(in: context, "hello", 15)

        let key = NodeWrappedDataKey<String>()
        let obj = try NodeObject(in: context)
        try obj.setWrappedValue("hello", forKey: key)
        print("wrapped value: \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")
        try obj.setWrappedValue(nil, forKey: key)
        print("wrapped value (shouldn't be found): \(try obj.wrappedValue(forKey: key) ?? "NOT FOUND")")

        try withExtendedLifetime(context.global()) {
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
        let global = try context.global()
        let cleanupHandler = CleanupHandler(global: global)

        try context.setInstanceData(cleanupHandler, for: .init())

        let tsfn = try NodeThreadsafeFunction(asyncResourceName: "DISPATCH_CB", in: context) { ctx in
            print("dispatch callback")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            try? tsfn()
        }
    }

}

import NodeAPI
import Foundation

@main struct NativeStuff: NodeModule {

    var exports: NodeValueConvertible

    init(context: NodeContext) throws {
        let captured = try NodeString("hi", in: context)
        try context.global().setTimeout(in: context, NodeFunction(in: context) { ctx, _, _ in
            print("Called our timeout! Captured: \(captured)")
            return try ctx.undefined()
        }, 1000)

        let res = try context.run(script: "[1, 15]").as(NodeObject.self)
        let num = try res[1].get(in: context).as(NodeNumber.self)
        print("Num: \(num)")

        print("Symbol.iterator is a \(try context.global().Symbol.iterator.get(in: context).type())")

        let strObj = try context.run(script: "('hello')")
        print("'\(strObj)' is a \(try strObj.type())")

        let doStuff = try NodeFunction(name: "doStuff", in: context) { ctx, this, args in
            print("Called! Arg 0: \(try args.first?.type() ?? .undefined)")
            return 5
        }
        exports = doStuff
        try doStuff(in: context, "hello", 15)

        let obj = try NodeObject(in: context)
        let tag = UUID()
        try obj.setTypeTag(tag)
        print("Has random tag (should be false): \(try obj.hasTypeTag(UUID()))")
        print("Has our tag (should be true): \(try obj.hasTypeTag(tag))")
        try withExtendedLifetime(context.global()) {
            print("First copy of global: \($0)")
        }
        let global = try context.global()
        try context.addCleanupHook {
            _ = global
            print("Cleanup!")
        }

        let tsfn = try NodeThreadsafeFunction(asyncResourceName: "DISPATCH_CB", in: context) { ctx in
            print("dispatch callback")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            try? tsfn()
        }
    }

}

import NodeAPI
import Foundation

@main struct NativeStuff: NodeModule {

    var exports: NodeValueConvertible

    init(context: NodeContext) throws {
        let res = try context.run(script: "[1, 15]").as(NodeObject.self)
        let num = try res[1].get(in: context).as(NodeNumber.self)
        print("Num: \(num)")

        let strObj = try context.run(script: "('hello')")
        print("type: \(try strObj.type())")
//        let str = try NodeString(NodeSymbol(description: "hi", in: environment), in: environment) // try NodeString(NodeNumber(double: 5, in: environment), in: environment)
        print("Str: \(strObj)")

        let doStuff = try NodeFunction(in: context, name: "doStuff") { ctx, this, args in
            print("Called! Arg 0: \(try args.first?.type() ?? .undefined)")
            return try ctx.undefined()
        }
        exports = doStuff
        try doStuff(in: context, "hello", 15)

        let obj = try NodeObject(newObjectIn: context)
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
    }

}

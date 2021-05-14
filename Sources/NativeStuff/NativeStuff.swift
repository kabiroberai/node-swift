import NodeAPI
import Foundation

@main struct NativeStuff: NodeModule {

    var exports: NodeValueConvertible

    init(environment: NodeEnvironment) throws {
        let strObj = try environment.run(script: "('hello')")
        print("type: \(try strObj.type(in: environment))")
//        let str = try NodeString(NodeSymbol(description: "hi", in: environment), in: environment) // try NodeString(NodeNumber(double: 5, in: environment), in: environment)
        print("Str: \(Result { try NodeString(strObj, in: environment).value(in: environment) })")

        let doStuff = try NodeFunction(in: environment, name: "doStuff") { env, this, args in
            print("Called!")
            return try NodeValue(undefinedIn: env)
        }
        exports = doStuff
        let obj = try NodeObject(NodeBool(value: true, in: environment), in: environment)
        let tag = UUID()
        try obj.setTypeTag(tag, in: environment)
        print("Has random tag (should be false): \(try obj.hasTypeTag(UUID(), in: environment))")
        print("Has our tag (should be true): \(try obj.hasTypeTag(tag, in: environment))")
        try withExtendedLifetime(environment.globalObject()) {
            print("First copy of global: \($0)")
        }
        let global = try environment.globalObject()
        print("typeof global == \(try global.type(in: environment))")
        try environment.addCleanupHook {
            print("Cleanup. Global: \(global)")
        }
    }

}

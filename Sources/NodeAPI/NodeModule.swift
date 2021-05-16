import CNodeAPI

public protocol NodeModule {
    static var name: String { get }
    init(context: NodeContext) throws
    var exports: NodeValueConvertible { get }
}

// since this library is statically linked, there should be
// exactly one module that we load and therefore we can use
// a global variable for its type, since otherwise we'd have
// to somehow pass a context to the registerModule function.
// We can't use a block because nm_register_func needs to be
// compatible with @convention(c)
private var globalModule: NodeModule.Type?

private func registerModule(rawEnv: napi_env!, exports: napi_value!) -> napi_value? {
    // the passed in exports is merely a convenience
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        try globalModule!
            .init(context: ctx)
            .exports
            .rawValue(in: ctx)
    }
}

extension NodeModule {
    public static var name: String {
        var fullName = "\(self)"
        let suffix = "Module"
        if fullName.hasSuffix(suffix) {
            fullName.removeLast(suffix.count)
        }
        return fullName
    }

    public static func main() {
        // just in case main is called multiple times
        guard globalModule == nil else { return }

        var rawMod = napi_module()
        rawMod.nm_version = NAPI_MODULE_VERSION
        rawMod.nm_filename = UnsafePointer(strdup(#file))
        rawMod.nm_register_func = registerModule
        rawMod.nm_modname = UnsafePointer(strdup(name))

        let mod = UnsafeMutablePointer<napi_module>.allocate(capacity: 1)
        mod.initialize(to: rawMod)

        globalModule = Self.self

        napi_module_register(mod)
    }
}

import CNodeAPI

public protocol NodeModule {
    static var name: String { get }
    init() throws
    var exports: NodeValueConvertible { get }
}

// since this library is statically linked, there should be
// exactly one module that we load and therefore we can use
// a global variable for its type, since otherwise we'd have
// to somehow pass a context to the registerModule function.
// We can't use a block because nm_register_func needs to be
// compatible with @convention(c)
private var globalModule: NodeModule.Type?

private func registerModule(rawEnv: napi_env!, exports _: napi_value!) -> napi_value? {
    // the passed in `exports` is merely a convenience, ignore it
    NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        try globalModule!.init().exports.rawValue()
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

        let modname = UnsafePointer(name.copiedCString())

        var rawMod = napi_module()
        rawMod.nm_version = NAPI_MODULE_VERSION
        rawMod.nm_filename = modname
        rawMod.nm_modname = modname

        // TODO: If we add dynamic linking support, we should make this a libffi-like closure
        // which captures the current module type.
        // Note that while TLS seems like a good option at first, it won't work because
        // if the library is loaded again (eg by a worker thread) since main isn't called the
        // second time, instead Node uses a cached copy of the napi_module from the global handle map:
        // https://github.com/nodejs/node/blob/a9dd03b1ec89a75186f05967fc76ec0704050c36/src/node_binding.cc#L489
        rawMod.nm_register_func = registerModule

        let mod = UnsafeMutablePointer<napi_module>.allocate(capacity: 1)
        mod.initialize(to: rawMod)

        globalModule = Self.self

        napi_module_register(mod)
    }
}

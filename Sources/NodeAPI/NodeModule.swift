import CNodeAPI
import Foundation

public protocol NodeModule {
    static var name: String { get }
    init() throws
    var exports: NodeValueConvertible { get }
}

// see comments in CNodeAPI/node_init.c, NodeSwiftHost/ctor.c

private var moduleMapping: [UnsafeRawPointer: NodeModule.Type] = [:]
private let moduleLock = NSLock()

@_cdecl("node_swift_addon_register_func") func registerModule(
    rawEnv: napi_env!,
    exports _: napi_value!,
    reg: napi_addon_register_func!
) -> napi_value? {
    let moduleType: NodeModule.Type
    do {
        moduleLock.lock()
        defer { moduleLock.unlock() }
        guard let _moduleType = moduleMapping[unsafeBitCast(reg, to: UnsafeRawPointer.self)] else {
            return nil
        }
        moduleType = _moduleType
    }
    // the passed in `exports` is merely a convenience, ignore it
    return NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        try moduleType.init().exports.rawValue()
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
        guard let reg = node_swift_get_thread_register_fn() else {
            return
        }

        let modname = UnsafePointer(name.copiedCString())

        var rawMod = napi_module()
        rawMod.nm_version = NAPI_MODULE_VERSION
        rawMod.nm_filename = modname
        rawMod.nm_modname = modname
        rawMod.nm_register_func = reg

        let mod = UnsafeMutablePointer<napi_module>.allocate(capacity: 1)
        mod.initialize(to: rawMod)

        napi_module_register(mod)

        let regRaw = unsafeBitCast(reg, to: UnsafeRawPointer.self)
        do {
            moduleLock.lock()
            defer { moduleLock.unlock() }
            moduleMapping[regRaw] = self
        }
    }
}

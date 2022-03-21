@_implementationOnly import CNodeAPI
import Foundation

@NodeActor public protocol NodeModule {
    nonisolated static var name: String { get }
    init() throws
    var exports: NodeValueConvertible { get }
}

private class ModulePriv {
    let name: UnsafeMutablePointer<CChar>
    let kind: NodeModule.Type
    init(name: UnsafeMutablePointer<CChar>, kind: NodeModule.Type) {
        self.name = name
        self.kind = kind
    }
    deinit { name.deallocate() }
}

private let threadModuleKey = "NODE_SWIFT_MODULE"
nonisolated private var threadModule: UnsafeMutablePointer<napi_module>? {
    get { Thread.current.threadDictionary[threadModuleKey] as? UnsafeMutablePointer<napi_module> }
    set { Thread.current.threadDictionary[threadModuleKey] = newValue }
}

// we can't pass params to main, so use TLS to store the current module.
// This is then retrieved in NodeModule.main, and the NodeModule.Type
// is assigned to module.priv
@_cdecl("node_swift_main") @_spi(NodeAPI) public func _nodeSwiftInit(
    main: @convention(c) () -> Int,
    module: UnsafeMutableRawPointer!
) {
    threadModule = module.assumingMemoryBound(to: napi_module.self)
    defer { threadModule = nil }
    _ = main()
}

// see comment in NodeSwiftHost/ctor.c
@NodeActor(unsafe) @_cdecl("node_swift_addon_register_func") @_spi(NodeAPI) public func _registerNodeSwiftModule(
    rawEnv: OpaquePointer!,
    exports _: OpaquePointer!,
    module: UnsafeRawPointer!
) -> OpaquePointer? {
    let moduleType = Unmanaged<ModulePriv>
        .fromOpaque(module.assumingMemoryBound(to: napi_module.self).pointee.nm_priv)
        .takeUnretainedValue()
        .kind
    // the passed in `exports` is merely a convenience, ignore it
    return NodeContext.withContext(environment: NodeEnvironment(rawEnv)) { ctx in
        try moduleType.init().exports.rawValue()
    }
}

extension NodeModule {
    nonisolated public static var name: String {
        var fullName = "\(self)"
        let suffix = "Module"
        if fullName.hasSuffix(suffix) {
            fullName.removeLast(suffix.count)
        }
        return fullName
    }

    nonisolated public static func main() {
        guard let mod = threadModule else {
            nodeFatalError("NodeSwift module \(self) did not register itself correctly")
        }

        // strongly retains modname
        let priv = ModulePriv(name: name.copiedCString(), kind: Self.self)
        let modname = UnsafePointer(priv.name)

        mod.pointee.nm_version = NAPI_MODULE_VERSION
        mod.pointee.nm_filename = modname
        mod.pointee.nm_modname = modname
        mod.pointee.nm_priv = Unmanaged.passRetained(priv).toOpaque()

        napi_module_register(mod)
    }
}

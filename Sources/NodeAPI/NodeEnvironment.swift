import Foundation
import CNodeAPI

// A NodeEnvironment instance usually corresponds to a single callback
// into native code. You **must not** allow instances of this to escape
// the scope in which they were called.
public final class NodeEnvironment {
    let raw: napi_env
    let isManaged: Bool

    private init(raw: napi_env, isManaged: Bool) {
        self.raw = raw
        self.isManaged = isManaged
    }

    private class WeakBox<T: AnyObject> {
        weak var value: T?
        init(value: T) { self.value = value }
    }

    // a list of values created with this context
    private var values: [WeakBox<NodeValue>] = []
    func registerValue(_ value: NodeValue) {
        // if we're in debug mode, register the value even in
        // unmanaged mode, to allow us to do sanity checks
        #if !DEBUG
        guard isManaged else { return }
        #endif
        values.append(WeakBox(value: value))
    }

    private static func withRaw<T>(_ raw: napi_env, do action: (NodeEnvironment) throws -> T, isManaged: Bool) throws -> T {
        // TODO: Convert Swift errors -> JS exceptions?
        let ret: T
        #if DEBUG
        weak var weakEnv: NodeEnvironment?
        defer {
            if let weakEnv = weakEnv {
                fatalError("\(weakEnv) escaped its context")
            }
        }
        #endif
        do {
            let env = NodeEnvironment(raw: raw, isManaged: isManaged)
            // delete dead refs from any previous envs
            try? env.swiftContext().deleteDeadRefs(env: env)
            ret = try action(env)
            if isManaged {
                for val in env.values {
                    try val.value?.persist(in: env)
                }
                env.values.removeAll()
            } else {
                #if DEBUG
                if let escaped = env.values.lazy.compactMap({ $0.value }).first {
                    fatalError("\(escaped) escaped unmanaged NodeEnvironment")
                }
                #endif
            }
            #if DEBUG
            weakEnv = env
            #endif
        }
        return ret
    }

    // This should be called at any entrypoint into our code from JS, with the
    // passed in napi_env.
    //
    // Upon completion of `action`, we can persist any node values that were
    // escaped, and perform other necessary cleanup.
    static func withRaw<T>(_ raw: napi_env, do action: (NodeEnvironment) throws -> T) throws -> T {
        try withRaw(raw, do: action, isManaged: true)
    }

    // Calls `action` with a NodeEnvironment which does not manage NodeValueConvertible
    // instances created using it. That is, the new environment will assume that
    // NodeValueConvertible instances created with it do not escape its own lifetime,
    // which in turn is exactly the lifetime of the closure. This trades away safety for
    // performance.
    public func withUnmanaged<T>(do action: (NodeEnvironment) throws -> T) throws -> T {
        // at the moment, NodeValueConvertibles created inside the closure are
        // technically valid for the same duration as the *receiver* but this is
        // an implementation detail, and NodeValueConvertibles escaping the closure
        // is considered undefined behavior (which we do try to catch anyway in
        // debug builds).
        try Self.withRaw(raw, do: action, isManaged: false)
    }
}

// MARK: - Values

// TODO: Figure out how we want to represent native literals as node values
// (ExpressibleBy*Literal or by making the native types conform to
// NodeValueConvertible?)
public protocol NodeValueConvertible {
    func nodeValue(in env: NodeEnvironment) throws -> NodeValue
}
protocol NodeValueStorage: NodeValueConvertible {
    var storedValue: NodeValue { get }
}
extension NodeValueStorage {
    public func nodeValue(in env: NodeEnvironment) throws -> NodeValue {
        storedValue
    }
}

public final class NodeValue: NodeValueStorage {
    private enum Guts {
        case unmanaged(napi_value)
        case managed(napi_ref, NodeSwiftContext)
    }

    public var storedValue: NodeValue { self }

    private var guts: Guts
    init(raw: napi_value, in env: NodeEnvironment) {
        self.guts = .unmanaged(raw)
        // this isn't the most performant solution to escaping NodeValues but
        // it's worth noting that even JSC seems to do something similar:
        // https://github.com/WebKit/WebKit/blob/dc23fbec330747c0fcd0e068c9103c05c65e4bf1/Source/JavaScriptCore/API/JSWrapperMap.mm
        // Also if users really need performance they can use
        // NodeEnvironment.withUnmanaged
        env.registerValue(self)
    }

    func persist(in env: NodeEnvironment) throws {
        print("Persisting \(self)")
        switch guts {
        case .managed:
            break // already persisted
        case .unmanaged(let raw):
            var ref: napi_ref!
            try env.check(napi_create_reference(env.raw, raw, 1, &ref))
            self.guts = .managed(ref, try env.swiftContext())
        }
    }

    func rawValue(in env: NodeEnvironment) throws -> napi_value {
        switch guts {
        case .unmanaged(let val):
            return val
        case .managed(let ref, _):
            var val: napi_value!
            try env.check(napi_get_reference_value(env.raw, ref, &val))
            return val
        }
    }

    deinit {
        switch guts {
        case .unmanaged:
            print("Deinit unmanaged \(self)")
            break
        case let .managed(ref, ctx):
            print("Register managed \(self) for deinit")
            ctx.addDeadRef(ref)
        }
    }
}

// MARK: - Cleanup Hooks

public final class CleanupHook {
    fileprivate let hook: () -> Void
    fileprivate init(hook: @escaping () -> Void) {
        self.hook = hook
    }
}

private func cleanupHook(payload: UnsafeMutableRawPointer?) {
    payload.map { Unmanaged<CleanupHook>.fromOpaque($0) }?
        .takeUnretainedValue().hook()
}

extension NodeEnvironment {
    @discardableResult
    public func addCleanupHook(action: @escaping () -> Void) throws -> CleanupHook {
        let token = CleanupHook(hook: action)
        try check(napi_add_env_cleanup_hook(
            raw, cleanupHook(payload:),
            Unmanaged.passRetained(token).toOpaque()
        ))
        return token
    }

    public func removeCleanupHook(_ hook: CleanupHook) throws {
        let arg = Unmanaged.passUnretained(hook)
        defer { arg.release() }
        try check(napi_remove_env_cleanup_hook(raw, cleanupHook(payload:), arg.toOpaque()))
    }

    // TODO: Support async cleanup?
}

// MARK: - Scopes

extension NodeEnvironment {

    public func withScope(perform action: @escaping () throws -> Void) throws {
        var scope: napi_handle_scope!
        try check(napi_open_handle_scope(raw, &scope))
        defer { napi_close_handle_scope(raw, scope) }
        try action()
    }

    public func withScope(perform action: @escaping () throws -> NodeValue) throws -> NodeValue {
        var scope: napi_handle_scope!
        try check(napi_open_escapable_handle_scope(raw, &scope))
        defer { napi_close_escapable_handle_scope(raw, scope) }
        let val = try action()
        var escaped: napi_value!
        try check(napi_escape_handle(raw, scope, val.rawValue(in: self), &escaped))
        return NodeValue(raw: escaped, in: self)
    }

    public func withScope(perform action: @escaping () throws -> NodeValue?) throws -> NodeValue? {
        struct NilValueError: Error {}
        do {
            return try withScope { () throws -> NodeValue in
                if let val = try action() {
                    return val
                } else {
                    throw NilValueError()
                }
            }
        } catch is NilValueError {
            return nil
        }
    }

}

// MARK: - Misc

public struct NodeVersion {
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32
    public let release: String

    init(raw: napi_node_version) {
        self.major = raw.major
        self.minor = raw.minor
        self.patch = raw.patch
        self.release = String(cString: raw.release)
    }
}

extension NodeEnvironment {

    public func globalObject() throws -> NodeValue {
        var val: napi_value!
        try check(napi_get_global(raw, &val))
        return NodeValue(raw: val, in: self)
    }

    public func nodeVersion() throws -> NodeVersion {
        // "The returned buffer is statically allocated and does not need to be freed"
        var version: UnsafePointer<napi_node_version>!
        try check(napi_get_node_version(raw, &version))
        return NodeVersion(raw: version.pointee)
    }

    public func apiVersion() throws -> UInt32 {
        var version: UInt32 = 0
        try check(napi_get_version(raw, &version))
        return version
    }

    // returns the adjusted value
    @discardableResult
    public func adjustExternalMemory(byBytes change: Int64) throws -> Int64 {
        var adjusted: Int64 = 0
        try check(napi_adjust_external_memory(raw, change, &adjusted))
        return adjusted
    }

    @discardableResult
    public func run(script: String) throws -> NodeValue {
        let nodeScript = try NodeString(script, in: self)
        var val: napi_value!
        try check(napi_run_script(raw, nodeScript.nodeValue(in: self).rawValue(in: self), &val))
        return NodeValue(raw: val, in: self)
    }

}

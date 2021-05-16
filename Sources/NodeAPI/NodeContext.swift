import Foundation
import CNodeAPI

private extension Thread {
    private static let contextKey = ObjectIdentifier(NodeContext.self)
    func withContextStack<T>(_ action: (inout [NodeContext]) throws -> T) rethrows -> T {
        var stack = threadDictionary[Self.contextKey] as? [NodeContext] ?? []
        let ret = try action(&stack)
        threadDictionary[Self.contextKey] = stack
        return ret
    }
}

// A call context that manages allocations in native code.
// You **must not** allow NodeContext instances to escape
// the scope in which they were called.
public final class NodeContext {
    let environment: NodeEnvironment
    let isManaged: Bool

    private init(environment: NodeEnvironment, isManaged: Bool) {
        self.environment = environment
        self.isManaged = isManaged
    }

    private class WeakBox<T: AnyObject> {
        weak var value: T?
        init(value: T) { self.value = value }
    }

    // a list of values created with this context
    private var values: [WeakBox<NodeValueBase>] = []
    func registerValue(_ value: NodeValueBase) {
        // if we're in debug mode, register the value even in
        // unmanaged mode, to allow us to do sanity checks
        #if !DEBUG
        guard isManaged else { return }
        #endif
        values.append(WeakBox(value: value))
    }

    private static func withContext<T>(
        environment env: NodeEnvironment,
        isManaged: Bool,
        do action: (NodeContext) throws -> T
    ) throws -> T {
        // TODO: Convert Swift errors -> JS exceptions?
        // note: if we do that, we should special-case stuff like
        // NodeError.Code.pendingException
        let ret: T
        #if DEBUG
        weak var weakCtx: NodeContext?
        defer {
            if let weakCtx = weakCtx {
                fatalError("\(weakCtx) escaped its expected scope")
            }
        }
        #endif
        do {
            let ctx = NodeContext(environment: env, isManaged: isManaged)
            Thread.current.withContextStack { $0.append(ctx) }
            defer { Thread.current.withContextStack { _ = $0.removeLast() } }
            // delete dead refs from any previous envs
            try? env.instanceData().deleteDeadRefs()
            ret = try action(ctx)
            if isManaged {
                for val in ctx.values {
                    try val.value?.persist()
                }
                ctx.values.removeAll()
            } else {
                #if DEBUG
                if let escaped = ctx.values.lazy.compactMap({ $0.value }).first {
                    fatalError("\(escaped) escaped unmanaged NodeContext")
                }
                #endif
            }
            #if DEBUG
            weakCtx = ctx
            #endif
        }
        return ret
    }

    // This should be called at any entrypoint into our code from JS, with the
    // passed in environment.
    //
    // Upon completion of `action`, we can persist any node values that were
    // escaped, and perform other necessary cleanup.
    static func withContext<T>(environment: NodeEnvironment, do action: (NodeContext) throws -> T) throws -> T {
        try withContext(environment: environment, isManaged: true, do: action)
    }

    // Calls `action` with a NodeContext which does not manage NodeValueConvertible
    // instances created using it. That is, the new context will assume that
    // NodeValueConvertible instances created with it do not escape its own lifetime,
    // which in turn is exactly the lifetime of the closure. This trades away safety for
    // performance.
    public func withUnmanaged<T>(do action: (NodeContext) throws -> T) throws -> T {
        try Self.withContext(environment: environment, isManaged: false, do: action)
    }

    // similar to withUnmanaged but creates a brand new context. For use internally
    // when a temporary value is needed but the method doesn't have access to a
    // context
    static func withUnmanagedContext<T>(environment: NodeEnvironment, do action: (NodeContext) throws -> T) throws -> T {
        try withContext(environment: environment, do: action)
    }

    public static var current: NodeContext {
        guard let last = Thread.current.withContextStack(\.last) else {
            fatalError("There is no current NodeContext")
        }
        return last
    }
}

// MARK: - Scopes

extension NodeContext {

    public func withScope(perform action: @escaping () throws -> Void) throws {
        var scope: napi_handle_scope!
        try environment.check(napi_open_handle_scope(environment.raw, &scope))
        defer { napi_close_handle_scope(environment.raw, scope) }
        try action()
    }

    public func withScope<V: NodeValue>(perform action: @escaping () throws -> V) throws -> V {
        var scope: napi_handle_scope!
        try environment.check(napi_open_escapable_handle_scope(environment.raw, &scope))
        defer { napi_close_escapable_handle_scope(environment.raw, scope) }
        let val = try action()
        var escaped: napi_value!
        try environment.check(napi_escape_handle(environment.raw, scope, val.base.rawValue(), &escaped))
        return NodeValueBase(raw: escaped, in: self).as(V.self)
    }

    private struct NilValueError: Error {}

    public func withScope<V: NodeValue>(perform action: @escaping () throws -> V?) throws -> V? {
        do {
            return try withScope { () throws -> V in
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

// MARK: - Cleanup Hooks

public final class CleanupHook {
    enum Hook {
        case sync(() -> Void)
        case async((@escaping () -> Void) -> Void)
    }
    let hook: Hook
    var asyncHandle: napi_async_cleanup_hook_handle?
    fileprivate init(hook: Hook) {
        self.hook = hook
    }
}

private func cCleanupHook(payload: UnsafeMutableRawPointer?) {
    guard let payload = payload else { return }
    let hook = Unmanaged<CleanupHook>.fromOpaque(payload).takeUnretainedValue()
    switch hook.hook {
    case .sync(let callback):
        callback()
    case .async:
        break
    }
}

private func cAsyncCleanupHook(handle: napi_async_cleanup_hook_handle!, payload: UnsafeMutableRawPointer!) {
    guard let payload = payload else { return }
    let hook = Unmanaged<CleanupHook>.fromOpaque(payload).takeUnretainedValue()
    switch hook.hook {
    case .sync:
        break
    case .async(let callback):
        callback { napi_remove_async_cleanup_hook(handle) }
    }
}

extension NodeContext {
    @discardableResult
    public func addCleanupHook(action: @escaping () -> Void) throws -> CleanupHook {
        let token = CleanupHook(hook: .sync(action))
        try environment.check(napi_add_env_cleanup_hook(
            environment.raw, cCleanupHook,
            Unmanaged.passRetained(token).toOpaque()
        ))
        return token
    }

    // action must call the passed in completion handler once it is done with
    // its cleanup
    public func addAsyncCleanupHook(action: @escaping (@escaping () -> Void) -> Void) throws -> CleanupHook {
        let token = CleanupHook(hook: .async(action))
        try environment.check(napi_add_async_cleanup_hook(
            environment.raw,
            cAsyncCleanupHook(handle:payload:),
            Unmanaged.passRetained(token).toOpaque(),
            &token.asyncHandle
        ))
        return token
    }

    public func removeCleanupHook(_ hook: CleanupHook) throws {
        let arg = Unmanaged.passUnretained(hook)
        defer { arg.release() }
        switch hook.hook {
        case .sync:
            try environment.check(
                napi_remove_env_cleanup_hook(
                    environment.raw, cCleanupHook, arg.toOpaque()
                )
            )
        case .async:
            try environment.check(
                napi_remove_async_cleanup_hook(hook.asyncHandle!)
            )
        }
    }
}

// MARK: - Globals

extension NodeContext {

    public func global() throws -> NodeObject {
        var val: napi_value!
        try environment.check(napi_get_global(environment.raw, &val))
        return NodeValueBase(raw: val, in: self).as(NodeObject.self)
    }

    public func null() throws -> NodeValue {
        var val: napi_value!
        try environment.check(napi_get_null(environment.raw, &val))
        return NodeValueBase(raw: val, in: self).as(AnyNodeValue.self)
    }

    public func undefined() throws -> NodeValue {
        var val: napi_value!
        try environment.check(napi_get_undefined(environment.raw, &val))
        return NodeValueBase(raw: val, in: self).as(AnyNodeValue.self)
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

extension NodeContext {

    public func nodeVersion() throws -> NodeVersion {
        // "The returned buffer is statically allocated and does not need to be freed"
        var version: UnsafePointer<napi_node_version>!
        try environment.check(napi_get_node_version(environment.raw, &version))
        return NodeVersion(raw: version.pointee)
    }

    public func apiVersion() throws -> Int {
        var version: UInt32 = 0
        try environment.check(napi_get_version(environment.raw, &version))
        return Int(version)
    }

    // returns the adjusted value
    @discardableResult
    public func adjustExternalMemory(byBytes change: Int64) throws -> Int64 {
        var adjusted: Int64 = 0
        try environment.check(napi_adjust_external_memory(environment.raw, change, &adjusted))
        return adjusted
    }

    @discardableResult
    public func run(script: String) throws -> NodeValue {
        var val: napi_value!
        try environment.check(
            napi_run_script(
                environment.raw,
                script.rawValue(in: self),
                &val
            )
        )
        return NodeValueBase(raw: val, in: self).as(AnyNodeValue.self)
    }

}

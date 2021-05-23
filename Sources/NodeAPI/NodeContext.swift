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

    // a list of values created with this context
    private var values: [WeakBox<NodeValueBase>] = []
    func registerValue(_ value: NodeValueBase) {
        // if we're in debug mode, register the value even in
        // unmanaged mode, to allow us to do sanity checks
        #if !DEBUG
        guard isManaged else { return }
        #endif
        values.append(WeakBox(value))
    }

    private static func withContext<T>(
        environment env: NodeEnvironment,
        isTopLevel: Bool,
        do action: (NodeContext) throws -> T
    ) throws -> T {
        let ret: T
        #if DEBUG
        weak var weakCtx: NodeContext?
        defer {
            if let weakCtx = weakCtx {
                nodeFatalError("\(weakCtx) escaped its expected scope")
            }
        }
        #endif
        do {
            let ctx = NodeContext(environment: env, isManaged: isTopLevel)
            Thread.current.withContextStack { $0.append(ctx) }
            defer { Thread.current.withContextStack { _ = $0.removeLast() } }
            do {
                ret = try action(ctx)
                if isTopLevel {
                    for val in ctx.values {
                        try val.value?.persist(in: ctx)
                    }
                    ctx.values.removeAll()
                } else {
                    #if DEBUG
                    if let escaped = ctx.values.lazy.compactMap({ $0.value }).first {
                        nodeFatalError("\(escaped) escaped unmanaged NodeContext")
                    }
                    #endif
                }
            } catch let error where isTopLevel {
                switch error {
                case let throwable as NodeThrowable:
                    try? ctx.throw(throwable)
                // TODO: handle specific error types
                // and let's maybe not throw a *string* in the general case?
//                case let error as NodeAPIError:
//                    break
//                case let error where type(of: error) is NSError.Type:
//                    let cocoaError = error as NSError
//                    break
                case let error:
                    try? ctx.throw(NodeThrowable("\(type(of: error)): \(error)".nodeValue(in: ctx)))
                    break
                }
                // we have to bail before the return statement somehow.
                // isTopLevel:true is accompanied by try? so what we
                // throw here doesn't really matter
                throw error
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
    static func withContext<T>(environment: NodeEnvironment, do action: (NodeContext) throws -> T) -> T? {
        try? withContext(environment: environment, isTopLevel: true, do: action)
    }

    // same as below but sometimes we want an unmanaged context (for internal use)
    // without using an existing managed context so calling this directly suffices
    static func withUnmanagedContext<T>(environment: NodeEnvironment, do action: (NodeContext) throws -> T) throws -> T {
        try withContext(environment: environment, isTopLevel: false, do: action)
    }

    // Calls `action` with a NodeContext which does not manage NodeValueConvertible
    // instances created using it. That is, the new context will assume that
    // NodeValueConvertible instances created with it do not escape its own lifetime,
    // which in turn is exactly the lifetime of the closure. This trades away safety for
    // performance.
    public func withUnmanaged<T>(do action: (NodeContext) throws -> T) throws -> T {
        try Self.withUnmanagedContext(environment: environment, do: action)
    }

    // TODO: Add the ability to escape a single NodeValue from withUnmanaged

    // this is for internal use. In user code, errors that bubble up to the top
    // will automatically be thrown to JS.
    private func `throw`(_ throwable: NodeThrowable) throws {
        try environment.check(napi_throw(environment.raw, throwable.exception.rawValue(in: self)))
    }

    public func throwUncaught(_ throwable: NodeThrowable) throws {
        try environment.check(
            napi_fatal_exception(environment.raw, throwable.exception.rawValue(in: self))
        )
    }

    public static var current: NodeContext {
        guard let last = Thread.current.withContextStack(\.last) else {
            nodeFatalError("There is no current NodeContext")
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
        return try NodeValueBase(raw: escaped, in: self).as(V.self)!
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

public final class AsyncCleanupHook {
    let callback: (@escaping () -> Void) -> Void
    var handle: napi_async_cleanup_hook_handle!
    fileprivate init(callback: @escaping (@escaping () -> Void) -> Void) {
        self.callback = callback
    }
}

private func cAsyncCleanupHook(handle: napi_async_cleanup_hook_handle!, payload: UnsafeMutableRawPointer!) {
    guard let payload = payload else { return }
    let hook = Unmanaged<AsyncCleanupHook>.fromOpaque(payload).takeRetainedValue()
    hook.callback { napi_remove_async_cleanup_hook(handle) }
}

extension NodeContext {

    // we choose not to implement sync cleanup hooks because those can be replicated by
    // using instanceData + a deinitializer

    // action must call the passed in completion handler once it is done with
    // its cleanup
    @discardableResult
    public func addAsyncCleanupHook(
        action: @escaping (@escaping () -> Void) -> Void
    ) throws -> AsyncCleanupHook {
        let token = AsyncCleanupHook(callback: action)
        try environment.check(napi_add_async_cleanup_hook(
            environment.raw,
            cAsyncCleanupHook,
            Unmanaged.passRetained(token).toOpaque(),
            &token.handle
        ))
        return token
    }

    public func removeCleanupHook(_ hook: AsyncCleanupHook) throws {
        let arg = Unmanaged.passUnretained(hook)
        defer { arg.release() }
        try environment.check(
            napi_remove_async_cleanup_hook(hook.handle)
        )
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

    public func global() throws -> NodeObject {
        var val: napi_value!
        try environment.check(napi_get_global(environment.raw, &val))
        return try NodeValueBase(raw: val, in: self).as(NodeObject.self)!
    }

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
        return try NodeValueBase(raw: val, in: self).concrete()
    }

}

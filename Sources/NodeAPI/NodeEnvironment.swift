@_implementationOnly import CNodeAPI

@dynamicMemberLookup
@NodeActor public final class NodeEnvironment {
    let _raw: UncheckedSendable<napi_env>
    nonisolated var raw: napi_env { _raw.value }

    nonisolated init(_ raw: napi_env) {
        self._raw = .init(raw)
    }

    public static var current: NodeEnvironment {
        NodeContext.current.environment
    }

    public nonisolated static func performUnsafe<T>(_ raw: OpaquePointer, perform: @NodeActor @Sendable () throws -> T) -> T? {
        NodeActor.unsafeAssumeIsolated { [env = NodeEnvironment(raw)] in
            NodeContext.withContext(environment: env) { _ in
                try perform()
            }
        }
    }

    func check(_ status: napi_status) throws {
        guard status != napi_ok else { return }

        // always catch JS errors and convert them into `NodeException`s.
        // If the user doesn't handle them, we'll convert them back into JS
        // exceptions in the top level NodeContext
        var isExceptionPending = false
        if status == napi_pending_exception {
            isExceptionPending = true
        } else {
            napi_is_exception_pending(raw, &isExceptionPending)
        }
        var exception: napi_value!
        if isExceptionPending {
            if napi_get_and_clear_last_exception(raw, &exception) == napi_ok {
                throw AnyNodeValue(raw: exception)
            } else {
                // there's a pending exception but we couldn't fetch it wtf
                throw NodeAPIError(.genericFailure)
            }
        }

        guard let code = NodeAPIError.Code(status: status) else { return }

        var extended: UnsafePointer<napi_extended_error_info>!
        let extendedCode = napi_get_last_error_info(raw, &extended)
        let details: NodeAPIError.Details?
        if extendedCode == napi_ok {
            details = .init(raw: extended.pointee)
        } else {
            details = nil
        }
        throw NodeAPIError(code, details: details)
    }

    static func check(_ status: napi_status) throws {
        guard status != napi_ok else { return }
        try current.check(status)
    }
}

// MARK: - Exceptions

extension NodeEnvironment {

    // this is for internal use. In user code, errors that bubble up to the top
    // will automatically be thrown to JS.
    func `throw`(_ error: Error) throws {
        try check(napi_throw(raw, AnyNodeValue(error: error).rawValue()))
    }

    public func throwUncaught(_ error: Error) throws {
        try check(
            napi_fatal_exception(raw, AnyNodeValue(error: error).rawValue())
        )
    }

}

// MARK: - Scopes

extension NodeEnvironment {

    public func withScope(perform action: () throws -> Void) throws {
        var scope: napi_handle_scope!
        try check(napi_open_handle_scope(raw, &scope))
        defer { napi_close_handle_scope(raw, scope) }
        try action()
    }

    public func withScope<V: NodeValue>(perform action: () throws -> V) throws -> V {
        var scope: napi_handle_scope!
        try check(napi_open_escapable_handle_scope(raw, &scope))
        defer { napi_close_escapable_handle_scope(raw, scope) }
        let val = try action()
        var escaped: napi_value!
        try check(napi_escape_handle(raw, scope, val.base.rawValue(), &escaped))
        return try NodeValueBase(raw: escaped, in: .current).as(V.self)!
    }

    public func withScope<V: NodeValue>(perform action: () throws -> V?) throws -> V? {
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

    // You guarantee that node objects created inside the `action` block will not escape
    // (except optionally the return value), in exchange for extra performance
    public func withUnmanagedContext<T>(perform action: () throws -> T) throws -> T {
        try NodeContext.withUnmanagedContext(environment: self) { _ in try action() }
    }

}

// MARK: - Cleanup Hooks

public final class CleanupHook {
    let callback: () -> Void
    init(callback: @escaping @Sendable () -> Void) {
        self.callback = callback
    }
}

private func cCleanupHook(_ payload: UnsafeMutableRawPointer?) {
    guard let payload = payload else { return }
    Unmanaged<CleanupHook>.fromOpaque(payload).takeRetainedValue().callback()
}

extension NodeEnvironment {

    @discardableResult
    public func addCleanupHook(
        action: @escaping @Sendable () -> Void
    ) throws -> CleanupHook {
        let token = CleanupHook(callback: action)
        try check(napi_add_env_cleanup_hook(
            raw,
            { cCleanupHook($0) },
            Unmanaged.passRetained(token).toOpaque()
        ))
        return token
    }

    public func removeCleanupHook(_ hook: CleanupHook) throws {
        let arg = Unmanaged.passUnretained(hook)
        try check(napi_remove_env_cleanup_hook(
            raw, { cCleanupHook($0) }, arg.toOpaque())
        )
        // only release if we succeed at removing the hook, otherwise
        // napi may still store a dangling pointer
        arg.release()
    }

}

// async hooks require NAPI 8+. sync requires 3+, so no
// need to check the version for sync.
#if !NAPI_VERSIONED || NAPI_GE_8

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

extension NodeEnvironment {

    // action must call the passed in completion handler once it is done with
    // its cleanup
    @discardableResult
    public func addCleanupHook(
        action: @escaping (@escaping () -> Void) -> Void
    ) throws -> AsyncCleanupHook {
        let token = AsyncCleanupHook(callback: action)
        try check(napi_add_async_cleanup_hook(
            raw,
            { cAsyncCleanupHook(handle: $0, payload: $1) },
            Unmanaged.passRetained(token).toOpaque(),
            &token.handle
        ))
        return token
    }

    // just some nice sugar
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func addCleanupHook(
        action: @escaping () async -> Void
    ) throws -> AsyncCleanupHook {
        try addCleanupHook { completion in
            Task {
                await action()
                completion()
            }
        }
    }

    public func removeCleanupHook(_ hook: AsyncCleanupHook) throws {
        let arg = Unmanaged.passUnretained(hook)
        try check(
            napi_remove_async_cleanup_hook(hook.handle)
        )
        arg.release()
    }

}

#endif

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

    // we could put this in NodeObject but that would allow calling
    // `global` on subclass types as well, which is confusing
    public var global: NodeObject {
        get throws {
            var val: napi_value!
            try check(napi_get_global(raw, &val))
            return try NodeValueBase(raw: val, in: .current).as(NodeObject.self)!
        }
    }

    public var nodeVersion: NodeVersion {
        get throws {
            // "The returned buffer is statically allocated and does not need to be freed"
            var version: UnsafePointer<napi_node_version>!
            try check(napi_get_node_version(raw, &version))
            return NodeVersion(raw: version.pointee)
        }
    }

    public var apiVersion: Int {
        get throws {
            var version: UInt32 = 0
            try check(napi_get_version(raw, &version))
            return Int(version)
        }
    }

    // returns the adjusted value
    @discardableResult
    public func adjustExternalMemory(byBytes change: Int64) throws -> Int64 {
        var adjusted: Int64 = 0
        try check(napi_adjust_external_memory(raw, change, &adjusted))
        return adjusted
    }

    @discardableResult
    public func run(script: String) throws -> AnyNodeValue {
        var val: napi_value!
        try check(
            napi_run_script(
                raw,
                script.rawValue(),
                &val
            )
        )
        return AnyNodeValue(raw: val)
    }

}

// MARK: - Convenience

extension NodeEnvironment {

    // equivalent to global.<key>
    public subscript(dynamicMember key: String) -> NodeObject.DynamicProperty {
        get throws {
            try global.property(forKey: key)
        }
    }

}

// equivalent to NodeEnvironment.current
// FIXME: This isn't dispatching onto NodeActor: SR-16034
@NodeActor public var Node: NodeEnvironment { .current }

// we want these to be usable even off of NodeActor, so they can't
// be NodeEnvironment instance vars because NodeEnvironment.current
// is NodeActor-isolated
nonisolated public var undefined: NodeValueConvertible { NodeDeferredValue { try NodeUndefined() } }
nonisolated public var null: NodeValueConvertible { NodeDeferredValue { try NodeNull() } }

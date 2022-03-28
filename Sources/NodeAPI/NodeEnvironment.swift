@_implementationOnly import CNodeAPI

@dynamicMemberLookup
@NodeActor public final class NodeEnvironment {
    let raw: napi_env

    nonisolated init(_ raw: napi_env) {
        self.raw = raw
    }

    public static var current: NodeEnvironment {
        NodeContext.current.environment
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
                throw NodeException(value: AnyNodeValue(raw: exception))
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

// MARK: - Instance Data

private typealias InstanceData = Box<[ObjectIdentifier: Any]>

private func finalizeInstanceData(
    env rawEnv: napi_env?,
    data: UnsafeMutableRawPointer?,
    hint: UnsafeMutableRawPointer?
) {
    guard let data = data else { return }
    Unmanaged<InstanceData>.fromOpaque(data).release()
}

extension NodeEnvironment {
    // TODO: don't use the instance data APIs at all;
    // other non-Swift native modules might try to set
    // instance_data and hence overwrite it, so using
    // this prop isn't a good idea. Instead, we can utilize
    // the fact that napi_env is unique per environment, to
    // store instance data in a global dict protected by a
    // (RW?)lock, keyed by the env's address. Values can be
    // removed from this dict via napi_add_env_cleanup_hook.
    //
    // Or, maybe use the thread ID? not sure if that's guaranteed
    // to be stable; napi_get_uv_event_loop could help since
    // maybe the uv loop address is stable. Or maybe set a
    // nodeSwiftEnvID prop on Node.global to represent the env ID
    private func instanceDataDict() throws -> InstanceData {
        var data: UnsafeMutableRawPointer?
        try check(napi_get_instance_data(raw, &data))
        if let data = data {
            return Unmanaged<InstanceData>.fromOpaque(data)
                .takeUnretainedValue()
        }
        let obj = InstanceData([:])
        let rawObj = Unmanaged.passRetained(obj).toOpaque()
        try check(napi_set_instance_data(raw, rawObj, finalizeInstanceData, nil))
        return obj
    }

    func instanceData(for id: ObjectIdentifier) throws -> Any? {
        try instanceDataDict().value[id]
    }

    func setInstanceData(_ value: Any?, for id: ObjectIdentifier) throws {
        try instanceDataDict().value[id] = value
    }
}

@NodeActor
@propertyWrapper public final class NodeInstanceData<Value> {
    private let defaultValue: Value

    private var key: ObjectIdentifier { ObjectIdentifier(self) }

    public func get() throws -> Value {
        try Node.instanceData(for: key) as? Value ?? defaultValue
    }

    public func set(to newValue: Value) throws {
        try Node.setInstanceData(newValue, for: key)
    }

    public var wrappedValue: Value {
        get { (try? get()) ?? defaultValue }
        set { try? set(to: newValue) }
    }

    public var projectedValue: NodeInstanceData<Value> { self }

    public nonisolated init(wrappedValue defaultValue: Value) {
        self.defaultValue = defaultValue
    }

    @available(*, unavailable, message: "NodeInstanceData cannot be an instance member")
    public static subscript(
        _enclosingInstance object: Never,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Never, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Never, NodeInstanceData<Value>>
    ) -> Value {
        get {}
    }
}

// MARK: - Exceptions

extension NodeEnvironment {

    // this is for internal use. In user code, errors that bubble up to the top
    // will automatically be thrown to JS.
    func `throw`(_ error: Error) throws {
        try check(napi_throw(raw, NodeException(error: error).value.rawValue()))
    }

    public func throwUncaught(_ error: Error) throws {
        try check(
            napi_fatal_exception(raw, NodeException(error: error).value.rawValue())
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

// MARK: - Async Cleanup Hooks

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

    // we choose not to implement sync cleanup hooks because those can be replicated by
    // using instanceData + a deinitializer

    // action must call the passed in completion handler once it is done with
    // its cleanup
    @discardableResult
    public func addAsyncCleanupHook(
        action: @escaping (@escaping () -> Void) -> Void
    ) throws -> AsyncCleanupHook {
        let token = AsyncCleanupHook(callback: action)
        try check(napi_add_async_cleanup_hook(
            raw,
            cAsyncCleanupHook,
            Unmanaged.passRetained(token).toOpaque(),
            &token.handle
        ))
        return token
    }

    // just some nice sugar
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func addAsyncCleanupHook(
        action: @escaping () async -> Void
    ) throws -> AsyncCleanupHook {
        try addAsyncCleanupHook { completion in
            Task {
                await action()
                completion()
            }
        }
    }

    public func removeCleanupHook(_ hook: AsyncCleanupHook) throws {
        let arg = Unmanaged.passUnretained(hook)
        defer { arg.release() }
        try check(
            napi_remove_async_cleanup_hook(hook.handle)
        )
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

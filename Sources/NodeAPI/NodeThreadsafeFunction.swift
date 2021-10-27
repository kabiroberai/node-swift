@_implementationOnly import CNodeAPI

private class Token {}
private typealias CallbackBox = Box<() throws -> Void>

private func cFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer?) {
    Unmanaged<Token>.fromOpaque(data).release()
}

private func cCallback(env: napi_env?, cb: napi_value?, context: UnsafeMutableRawPointer!, data: UnsafeMutableRawPointer!) {
    let callback = Unmanaged<CallbackBox>.fromOpaque(data).takeRetainedValue()

    guard let env = env else { return }

    NodeContext.withContext(environment: NodeEnvironment(env)) { ctx in
        try callback.value()
    }
}

// this is the only async API we implement because it's more or less isomorphic
// to napi_async_init+napi_[open|close]_callback_scope (which are in turn
// supersets of the other async APIs) and unlike the callback APIs, where you
// need to figure out how to get back onto the main event loop yourself
// (probably using libuv), this API does that for you.

// a queue that allows dispatching closures to the JS thread it was initialized on
// Unless specified otherwise, the APIs on this class are thread-safe
public final class NodeAsyncQueue {
    // the callbackHandle is effectively an atomic indicator of
    // whether the tsfn finalizer has been called. The only thing
    // holding a strong ref to this is the threadsafe
    // function itself, and that ref is released when cFinalizer
    // is invoked, therefore making this handle nil
    private weak var _tsfnToken: AnyObject?
    private var isValid: Bool { _tsfnToken != nil }

    // this property can be made publicly readable, but we'd need to make
    // it atomic or explicitly thread-unsafe
    private var keepsNodeThreadAlive: Bool

    private let environment: NodeEnvironment
    private let raw: napi_threadsafe_function

    // MUST be called from a JS thread
    public init(
        label: String,
        asyncResource: NodeObjectConvertible? = nil,
        keepsNodeThreadAlive: Bool = true,
        maxQueueSize: Int? = nil
    ) throws {
        let tsfnToken = Token()
        self._tsfnToken = tsfnToken
        let box = Unmanaged.passRetained(tsfnToken).toOpaque()
        var result: napi_threadsafe_function!
        environment = .current
        try environment.check(napi_create_threadsafe_function(
            environment.raw, nil,
            asyncResource?.rawValue(), label.rawValue(),
            maxQueueSize ?? 0, 1,
            box, cFinalizer,
            nil, cCallback,
            &result
        ))
        self.raw = result
        // the initial value set by napi itself is `true`
        self.keepsNodeThreadAlive = true
        try setKeepsNodeThreadAlive(keepsNodeThreadAlive)
    }

    private static func check(_ status: napi_status) throws {
        if let errCode = NodeAPIError.Code(status: status) {
            throw NodeAPIError(errCode)
        }
    }

    // if isValid is false (i.e. callbackHandle has been released),
    // the tsfn finalizer has been called and so it's now invalid for
    // use. This can happen during napi_env teardown, in which case
    // the tsfn will have been invalidated without our explicitly asking
    // for it
    private func ensureValid() throws {
        guard isValid else {
            throw NodeAPIError(.closing)
        }
    }

    // makes any future calls to the threadsafe function return NodeAPIError(.closing)
    public func close() throws {
        try ensureValid()
        try Self.check(napi_acquire_threadsafe_function(raw))
        try Self.check(napi_release_threadsafe_function(raw, napi_tsfn_abort))
    }

    // Must be called from the associated JS thread. Determines whether the main thread
    // stays alive while the receiver is referenced from other threads
    public func setKeepsNodeThreadAlive(_ keepAlive: Bool) throws {
        guard keepAlive != keepsNodeThreadAlive else { return }
        try ensureValid()
        if keepAlive {
            try environment.check(
                napi_ref_threadsafe_function(environment.raw, raw)
            )
        } else {
            try environment.check(
                napi_unref_threadsafe_function(environment.raw, raw)
            )
        }
        keepsNodeThreadAlive = keepAlive
    }

    deinit {
        if isValid {
            napi_release_threadsafe_function(raw, napi_tsfn_release)
        }
    }

    // thread-safe. Will throw NodeAPIError(.closing) if another thread called abort()
    public func async(blocking: Bool = false, _ action: @escaping () throws -> Void) throws {
        try ensureValid()
        // `as AnyObject` should be faster than Box for classes, NS primitives
        let payload = CallbackBox(action)
        let unmanagedPayload = Unmanaged.passRetained(payload)
        let rawPayload = unmanagedPayload.toOpaque()
        do {
            try Self.check(
                napi_call_threadsafe_function(
                    raw, rawPayload,
                    blocking ? napi_tsfn_blocking : napi_tsfn_nonblocking
                )
            )
        } catch {
            unmanagedPayload.release()
        }
    }

}

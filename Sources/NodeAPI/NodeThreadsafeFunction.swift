import CNodeAPI

private func cFinalizer(rawEnv: napi_env!, data: UnsafeMutableRawPointer!, hint: UnsafeMutableRawPointer?) {
    Unmanaged<Box<AnyCallback>>.fromOpaque(data).release()
}

private func cCallback(env: napi_env?, cb: napi_value?, context: UnsafeMutableRawPointer!, data: UnsafeMutableRawPointer!) {
    // the callback persists across calls but input is specific to this call
    // which is why we only take the latter as retained. Also we need to
    // free the input regardless of whether the env is nil.
    let callback = Unmanaged<Box<AnyCallback>>.fromOpaque(context).takeUnretainedValue()
    let input = Unmanaged<AnyObject>.fromOpaque(data).takeRetainedValue()

    guard let env = env else { return }

    NodeContext.withContext(environment: NodeEnvironment(env)) { ctx in
        try callback.value(input)
    }
}

private typealias AnyCallback = (AnyObject) throws -> Void

// TODO: Maybe make this more like dispatch_async? We could make it so
// the tsfn initializer doesn't actually take the callback, and instead
// the user has to supply a callback while invoking the tsfn: so
//
// let tsfn = NodeThreadsafeFunction(asyncResourceName: "test", in: ctx)
// ... later, on another thread ...
// tsfn {
//     ... do stuff ...
// }
//
// This way the tsfn doesn't even have to be generic over Input, input can
// always be a `() throws -> Void`

// this is the only async API we implement because it's more or less isomorphic
// to napi_async_init+napi_[open|close]_callback_scope (which are in turn
// supersets of the other async APIs) and unlike the callback APIs, where you
// need to figure out how to get back onto the main event loop yourself
// (probably using libuv), this API does that for you.

// a function that can be called from non-JS threads
public final class NodeThreadsafeFunction<Input> {
    public typealias Callback = (Input) throws -> Void

    // the callbackHandle is effectively an atomic indicator of
    // whether the tsfn finalizer has been called. The only thing
    // holding a strong ref to this is the threadsafe
    // function itself, and that ref is released when cFinalizer
    // is invoked, therefore making this handle nil
    private weak var _callbackHandle: Box<AnyCallback>?
    private var isValid: Bool { _callbackHandle != nil }

    public private(set) var keepsMainThreadAlive: Bool
    private let environment: NodeEnvironment
    private let raw: napi_threadsafe_function
    // must be called from the main thread; and the callback will be called on
    // the main thread.
    public init(
        asyncResourceName: String,
        asyncResource: NodeObjectConvertible? = nil,
        keepsMainThreadAlive: Bool = true,
        maxQueueSize: Int? = nil,
        callback: @escaping Callback
    ) throws {
        let callbackHandle = Box<AnyCallback> { anyInput in
            try callback(anyInput as! Input)
        }
        self._callbackHandle = callbackHandle
        let box = Unmanaged.passRetained(callbackHandle).toOpaque()
        var result: napi_threadsafe_function!
        environment = .current
        try environment.check(napi_create_threadsafe_function(
            environment.raw, nil,
            asyncResource?.rawValue(), asyncResourceName.rawValue(),
            maxQueueSize ?? 0, 1,
            box, cFinalizer,
            box, cCallback,
            &result
        ))
        self.raw = result
        // the initial value set by napi itself is `true`
        self.keepsMainThreadAlive = true
        try setKeepsMainThreadAlive(keepsMainThreadAlive)
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
    public func abort() throws {
        try ensureValid()
        try Self.check(napi_acquire_threadsafe_function(raw))
        try Self.check(napi_release_threadsafe_function(raw, napi_tsfn_abort))
    }

    // Must be called from the main thread. Determines whether the main thread stays
    // alive while the receiver is referenced from other threads
    public func setKeepsMainThreadAlive(_ keepAlive: Bool) throws {
        guard keepAlive != keepsMainThreadAlive else { return }
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
        keepsMainThreadAlive = keepAlive
    }

    deinit {
        if isValid {
            napi_release_threadsafe_function(raw, napi_tsfn_release)
        }
    }

    // thread-safe. Will throw NodeAPIError(.closing) if another thread called abort()
    public func call(_ input: Input, blocking block: Bool = false) throws {
        try ensureValid()
        // `as AnyObject` should be faster than Box for classes, NS primitives
        let payload = input as AnyObject
        let unmanagedPayload = Unmanaged.passRetained(payload)
        let rawPayload = unmanagedPayload.toOpaque()
        do {
            try Self.check(
                napi_call_threadsafe_function(
                    raw, rawPayload,
                    block ? napi_tsfn_blocking : napi_tsfn_nonblocking
                )
            )
        } catch {
            unmanagedPayload.release()
        }
    }

    public func callAsFunction(_ input: Input, blocking block: Bool = false) throws {
        try call(input, blocking: block)
    }

}

extension NodeThreadsafeFunction where Input == Void {

    public convenience init(
        asyncResourceName: String,
        asyncResource: NodeObjectConvertible? = nil,
        keepsMainThreadAlive: Bool = true,
        maxQueueSize: Int? = nil,
        callback: @escaping () throws -> Void
    ) throws {
        try self.init(
            asyncResourceName: asyncResourceName,
            asyncResource: asyncResource,
            keepsMainThreadAlive: keepsMainThreadAlive,
            maxQueueSize: maxQueueSize
        ) { _ in try callback() }
    }

    public func call(blocking block: Bool = false) throws {
        try call((), blocking: block)
    }

    public func callAsFunction(_blocking block: Bool = false) throws {
        try call(blocking: block)
    }

}

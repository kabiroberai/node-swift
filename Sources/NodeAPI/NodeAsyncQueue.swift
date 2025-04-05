internal import CNodeAPI
import Foundation

extension NodeEnvironment {
    @NodeInstanceData private static var id: UUID?
    func instanceID() throws -> UUID {
        if let id = Self.id { return id }
        let id = UUID()
        Self.id = id
        return id
    }
}

private class Token {}
private typealias CallbackBox = Box<(NodeEnvironment) -> Void>

private func cCallback(
    env: napi_env?, cb: napi_value?,
    context: UnsafeMutableRawPointer!, data: UnsafeMutableRawPointer!
) {
    let callback = Unmanaged<CallbackBox>.fromOpaque(data).takeRetainedValue()

    guard let env = env else { return }

    // we DON'T create a new NodeContext here. See handle.deinit for rationale.
    callback.value(NodeEnvironment(env))
}

private let cCallbackC: napi_threadsafe_function_call_js = {
    cCallback(env: $0, cb: $1, context: $2, data: $3)
}

// this is the only async API we implement because it's more or less isomorphic
// to napi_async_init+napi_[open|close]_callback_scope (which are in turn
// supersets of the other async APIs) and unlike the callback APIs, where you
// need to figure out how to get back onto the main event loop yourself
// (probably using libuv), this API does that for you.

// a queue that allows dispatching closures to the JS thread it was initialized on.
public final class NodeAsyncQueue: @unchecked Sendable {
    // tsfnToken is effectively an atomic indicator of whether
    // the tsfn finalizer has been called. The only thing
    // holding a strong ref to this is the threadsafe
    // function itself, and that ref is released when cFinalizer
    // is invoked, therefore making this handle nil
    private weak var _tsfnToken: AnyObject?
    private var isValid: Bool { _tsfnToken != nil }

    let label: String
    let instanceID: UUID
    private let environment: NodeEnvironment
    private let raw: napi_threadsafe_function
    private weak var currentHandle: Handle?

    @NodeActor public init(
        label: String,
        asyncResource: NodeObjectConvertible? = nil,
        maxQueueSize: Int? = nil
    ) throws {
        self.label = label
        environment = .current
        self.instanceID = try environment.instanceID()
        let tsfnToken = Token()
        self._tsfnToken = tsfnToken
        let box = Unmanaged.passRetained(tsfnToken)
        var result: napi_threadsafe_function!
        do {
            try environment.check(napi_create_threadsafe_function(
                environment.raw, nil,
                asyncResource?.rawValue(), label.rawValue(),
                maxQueueSize ?? 0, 1,
                box.toOpaque(), { rawEnv, data, hint in
                    Unmanaged<Token>.fromOpaque(data!).release()
                },
                nil, cCallbackC,
                &result
            ))
        } catch {
            box.release() // we stan strong exception safety
            throw error
        }
        self.raw = result
        try environment.check(napi_unref_threadsafe_function(environment.raw, raw))
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
            throw NodeAPIError(.closing, message: "NodeAsyncQueue '\(label)' has been released")
        }
    }

    // makes any future calls to the threadsafe function return NodeAPIError(.closing)
    public func close() throws {
        try ensureValid()
        try Self.check(napi_acquire_threadsafe_function(raw))
        try Self.check(napi_release_threadsafe_function(raw, napi_tsfn_abort))
    }

    public class Handle: @unchecked Sendable {
        public let queue: NodeAsyncQueue

        @NodeActor fileprivate init(_ queue: NodeAsyncQueue) throws {
            let env = queue.environment
            try env.check(napi_ref_threadsafe_function(env.raw, queue.raw))
            self.queue = queue
        }

        deinit {
            let raw = UncheckedSendable(queue.raw)
            // capture raw right here since `queue` might be deinitialized
            // by the time we enter the closure. Also, we use the variant
            // of `run` that doesn't do NodeContext.withContext since that
            // would result in a new handle being created, meaning that we'd
            // effectively never end up with a nil currentHandle.
            try? queue.run { [weak queue] env in
                // unref isn't ref-counted (e.g. ref, ref, unref is equivalent
                // to ref, unref) so we only want to call it when we're really
                // sure we're done; that is, if we're the last handle to be
                // deinitialized
                guard queue?.currentHandle == nil else { return }
                // we aren't really isolated but this is necessary to suppress
                // warnings about accessing `env.raw` off of NodeActor
                NodeActor.unsafeAssumeIsolated {
                    _ = napi_unref_threadsafe_function(env.raw, raw.value)
                }
            }
        }
    }

    // returns a handle to the queue that keeps the node thread alive
    // while the handle is alive, even if the queue's own
    // keepsNodeThreadAlive is false
    @NodeActor public func handle() throws -> Handle {
        if let currentHandle = currentHandle {
            return currentHandle
        } else {
            let handle = try Handle(self)
            currentHandle = handle
            return handle
        }
    }

    deinit {
        if isValid {
            napi_release_threadsafe_function(raw, napi_tsfn_release)
        }
    }

    // will throw NodeAPIError(.closing) if another thread called abort()
    private func run(
        blocking: Bool = false,
        _ action: @escaping @Sendable (NodeEnvironment) -> Void
    ) throws {
        try ensureValid()
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

    public func run(
        blocking: Bool = false,
        @_implicitSelfCapture _ action: @escaping @Sendable @NodeActor () throws -> Void
    ) throws {
        try run(blocking: blocking) { env in
            NodeContext.withUnsafeEntrypoint(env) { _ in try action() }
        }
    }

    private enum RunState {
        case pending
        case running(Task<Void, Never>)
        case cancelled
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func run<T: Sendable>(
        blocking: Bool = false,
        resultType: T.Type = T.self,
        @_implicitSelfCapture body: @escaping @Sendable @NodeActor () async throws -> T
    ) async throws -> T {
        // TODO: Create a 'LockIsolated' helper type or use atomics here
        let lock = Lock()
        let state = UncheckedSendable(Box<RunState>(.pending))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                do {
                    try run(blocking: blocking) {
                        lock.withLock {
                            switch state.value.value {
                            case .cancelled:
                                cont.resume(throwing: CancellationError())
                            case .pending:
                                state.value.value = .running(Task {
                                    do {
                                        cont.resume(returning: try await body())
                                    } catch {
                                        cont.resume(throwing: error)
                                    }
                                })
                            case .running:
                                break // wat
                            }
                        }
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: { [state] in
            lock.withLock {
                switch state.value.value {
                case .pending:
                    state.value.value = .cancelled
                case .running(let task):
                    task.cancel()
                    state.value.value = .cancelled
                case .cancelled:
                    break // wat
                }
            }
        }
    }

}

extension NodeAsyncQueue: CustomStringConvertible {
    public var description: String {
        "<NodeAsyncQueue: \(label)>"
    }
}

extension NodeAsyncQueue.Handle: CustomStringConvertible {
    public var description: String {
        "<NodeAsyncQueue.Handle: \(queue.label)>"
    }
}

import Foundation
@_implementationOnly import CNodeAPI

extension NodeContext {
    // if we're on a node thread, run `action` on it
    @NodeActor(unsafe) static func runOnActor<T>(_ action: @NodeActor () throws -> T) rethrows -> T? {
        guard NodeContext.hasCurrent else { return nil }
        return try action()
    }
}

private enum TLS {
    // https://github.com/apple/swift-system/blob/8e3c23987f32d4f449c68ff4b702121025980a7c/Sources/System/Internals/Exports.swift#L128
    struct Key: RawRepresentable, ExpressibleByIntegerLiteral {
        #if os(Windows)
        typealias RawValue = DWORD
        #else
        typealias RawValue = pthread_key_t
        #endif
        let rawValue: RawValue
        init(_ value: RawValue) {
            self.rawValue = value
        }
        init(rawValue value: RawValue) {
            self.rawValue = value
        }
        init(integerLiteral value: RawValue) {
            self.rawValue = value
        }
    }
    static subscript(key: Key) -> UnsafeMutableRawPointer? {
        get {
            #if os(Windows)
            return FlsGetValue(key.rawValue)
            #else
            return pthread_getspecific(key.rawValue)
            #endif
        }
        set {
            #if os(Windows)
            guard FlsSetValue(key.rawValue, newValue) else {
                fatalError("Unable to set TLS")
            }
            #else
            guard 0 == pthread_setspecific(key.rawValue, newValue) else {
                fatalError("Unable to set TLS")
            }
            #endif
        }
    }
}

// https://github.com/apple/swift/blob/d0cc5757b914c694e2549a413fe7e96e328cca3e/include/swift/Runtime/ThreadLocalStorage.h#L74
// i'm not sure if this is ABI, but it's the best we have for now
private let swiftTaskKey: TLS.Key = 103

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private final class NodeExecutor: SerialExecutor {
    func enqueue(_ job: UnownedJob) {
        // temporarily spoof the current task so that we can access
        // its task-local storage. Here be dragons.
        let prevTask = TLS[swiftTaskKey]
        TLS[swiftTaskKey] = unsafeBitCast(job, to: UnsafeMutableRawPointer.self)
        let target = NodeActor.target
        TLS[swiftTaskKey] = prevTask

        guard let q = target?.queue else {
            nodeFatalError("There is no target NodeAsyncQueue associated with this Task")
        }

        let ref = asUnownedSerialExecutor()

        if q.instanceID == NodeContext.runOnActor({ try? Node.instanceID() }) {
            // if we're already on the right thread, skip a hop
            job._runSynchronously(on: ref)
        } else {
            do {
                try q.run { job._runSynchronously(on: ref) }
            } catch {
                nodeFatalError("Could not execute job on NodeActor: \(error)")
            }
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        .init(ordinary: self)
    }
}

// This isn't *actually* a single global actor. Rather, its associated
// serial executor runs jobs on the task-local "target" NodeAsyncQueue.
// As a result, if you switch Node instances (eg from the main thread
// onto a worker) you should still be wary of using values from one
// instance in another. Similarly, trying to run on NodeActor from a
// Task.detatched closure will crash.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@globalActor public actor NodeActor {
    private init() {}
    public static let shared = NodeActor()

    @TaskLocal public static var target: NodeAsyncQueue.Handle?

    private nonisolated let _unownedExecutor = NodeExecutor()
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        _unownedExecutor.asUnownedSerialExecutor()
    }

    public static func run<T: Sendable>(resultType: T.Type = T.self, body: @NodeActor @Sendable () throws -> T) async rethrows -> T {
        try await body()
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension Task where Failure == Never {
    // if it's absolutely necessary to create a detached task, use this
    // instead of Task.detached since the latter doesn't inherit any
    // task-locals, which means the current Node instance won't be
    // preserved; this explicitly restores the NodeAsyncQueue local.
    @discardableResult
    public static func nodeDetached(priority: TaskPriority? = nil, operation: @escaping @Sendable () async -> Success) -> Task<Success, Failure> {
        Task.detached(priority: priority) { [t = NodeActor.target] in
            await NodeActor.$target.withValue(t, operation: operation)
        }
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension Task where Failure == Error {
    @discardableResult
    public static func nodeDetached(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Success) -> Task<Success, Failure> {
        Task.detached(priority: priority) { [t = NodeActor.target] in
            try await NodeActor.$target.withValue(t, operation: operation)
        }
    }
}

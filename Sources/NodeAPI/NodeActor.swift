import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NodeAsyncQueue {
    @TaskLocal static var current: NodeAsyncQueue?
}

extension NodeContext {
    // if we're on a node thread, run `action` on it
    @NodeActor(unsafe) static func runOnActor<T>(_ action: @NodeActor () throws -> T) rethrows -> T? {
        guard NodeContext.hasCurrent else { return nil }
        return try action()
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private final class NodeExecutor: SerialExecutor {
    func enqueue(_ job: UnownedJob) {
        let ref = asUnownedSerialExecutor()

        guard let q = NodeAsyncQueue.current else {
            nodeFatalError("There is no NodeAsyncQueue associated with this Task")
        }

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
// serial executor runs jobs on the current task-local NodeAsyncQueue.
// As a result, if you switch Node instances (eg from the main thread
// onto a worker) you should still be wary of using values from one
// instance in another. Similarly, trying to run on NodeActor from a
// Task.detatched closure will crash.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
@globalActor public actor NodeActor {
    private init() {}
    public static let shared = NodeActor()

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
        Task.detached(priority: priority) { [q = NodeAsyncQueue.current] in
            await NodeAsyncQueue.$current.withValue(q, operation: operation)
        }
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension Task where Failure == Error {
    @discardableResult
    public static func nodeDetached(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Success) -> Task<Success, Failure> {
        Task.detached(priority: priority) { [q = NodeAsyncQueue.current] in
            try await NodeAsyncQueue.$current.withValue(q, operation: operation)
        }
    }
}

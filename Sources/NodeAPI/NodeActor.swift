import Foundation
@_implementationOnly import CNodeAPI

extension NodeContext {
    // if we're on a node thread, run `action` on it
    @NodeActor(unsafe) static func runOnActor<T>(_ action: @NodeActor () throws -> T) rethrows -> T? {
        guard NodeContext.hasCurrent else { return nil }
        return try action()
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension UnownedJob {
    func asCurrent<T>(work: () -> T) -> T {
        withoutActuallyEscaping(work) { work in
            var result: T!
            node_swift_as_current_task(unsafeBitCast(self, to: OpaquePointer.self), { ctx in
                Unmanaged<Box<() -> Void>>.fromOpaque(ctx).takeRetainedValue().value()
            }, Unmanaged.passRetained(Box<() -> Void> {
                result = work()
            }).toOpaque())
            return result
        }
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private final class NodeExecutor: SerialExecutor {
    func enqueue(_ job: UnownedJob) {
        // We want to access `job`'s task-local storage. To do so,
        // this temporarily swaps ResumeTask for our own function.
        // Then, swift_job_run is called, which sets the active task to
        // the receiver and invokes its ResumeTask. We then execute the
        // given closure, allowing us to grab task-local values. Finally,
        // we "suspend" the task and return ResumeTask to its old value.
        //
        // on Darwin we can instead replace the "current task" thread-local
        // (key 103) temporarily, but that isn't portable.
        //
        // This is sort of like inserting a "work(); await Task.yield()" block
        // at the top of the task, since when a Task awaits it similarly changes
        // the Resume function and suspends. Note that we can assume that this
        // is a Task and not a basic Job, because Executor.enqueue is only
        // called from swift_task_enqueue.
        let target = job.asCurrent { NodeActor.target }

        guard let q = target?.queue else {
            nodeFatalError("There is no target NodeAsyncQueue associated with this Task")
        }

        let ref = asUnownedSerialExecutor()

        if q.instanceID == NodeContext.runOnActor({ try? Node.instanceID() }) {
            // if we're already on the right thread, skip a hop
            job.runSynchronously(on: ref)
        } else {
            do {
                try q.run { job.runSynchronously(on: ref) }
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

    @TaskLocal static var target: NodeAsyncQueue.Handle?

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

import Foundation
import CNodeAPISupport
@_implementationOnly import CNodeAPI

extension NodeContext {
    // if we're on a node thread, run `action` on it
    static func runOnActor<T>(_ action: @NodeActor @Sendable () throws -> T) rethrows -> T? {
        guard NodeContext.hasCurrent else { return nil }
        return try NodeActor.unsafeAssumeIsolated(action)
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
    private let schedulerQueue = DispatchQueue(label: "NodeExecutorScheduler")

    fileprivate init() {
        // Swift often thinks that we're on the wrong executor, so we end up
        // with a lot of false alarms. This is what `checkIsolation` ostensibly
        // mitigates, but that method doesn't seem to be called in many
        // circumstances (pre macOS 15, but also on macOS 15 if the host node binary
        // is built with an older SDK.) Best we can do is disable the checks for now.
        setenv("SWIFT_UNEXPECTED_EXECUTOR_LOG_LEVEL", "0", 1)
    }

    func enqueue(_ job: UnownedJob) {
        schedulerQueue.async {
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
            //
            // Regarding `schedulerQueue.async`:
            // Pre Swift 6.0 we didn't need a scheduler queue as enqueue would always
            // run on the global queue. However, Swift 6 introduces optimizations in
            // Task dispatch that allow tasks to be enqueued more efficiently, including
            // that Task.init avoids a hop when possible. This, however, interferes with
            // our `job.asCurrent` code because `asCurrent` relies on there being no already-
            // running task (swift_job_run doesn't play well with nesting, it's possible but
            // requires more private APIs, cf [swift_task_startOnMainActor][1]). The simplest
            // solution is to hop onto our own queue for scheduling.
            //
            // [1]: https://github.com/apple/swift/blob/876c056153554f93b89dfd134794a05426ee789a/stdlib/public/Concurrency/Task.cpp#L1739
            let target = job.asCurrent { NodeActor.target }

            guard let q = target?.queue else {
                nodeFatalError("There is no target NodeAsyncQueue associated with this Task")
            }

            let ref = self.asUnownedSerialExecutor()

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

    func checkIsolated() {
        // TODO: crash if we're not on a Node thread
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

    private nonisolated let executor = NodeExecutor()
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    public static func run<T: Sendable>(resultType: T.Type = T.self, body: @NodeActor @Sendable () throws -> T) async rethrows -> T {
        try await body()
    }
}

extension NodeActor {
    public static func unsafeAssumeIsolated<T>(_ action: @NodeActor @Sendable () throws -> T) rethrows -> T {
        try withoutActuallyEscaping(action) {
            try unsafeBitCast($0, to: (() throws -> T).self)()
        }
    }

    public static func assumeIsolated<T>(
        _ action: @NodeActor @Sendable () throws -> T,
        file: StaticString = #fileID,
        line: UInt = #line
    ) rethrows -> T {
        guard NodeContext.hasCurrent else {
            nodeFatalError("NodeActor.assumeIsolated failed", file: file, line: line)
        }
        return try unsafeAssumeIsolated(action)
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

import Foundation
import CNodeAPISupport
internal import CNodeAPI

extension NodeEnvironment {
    @NodeInstanceData private static var defaultQueue: NodeAsyncQueue?
    func getDefaultQueue() throws -> NodeAsyncQueue {
        if let q = Self.defaultQueue { return q }
        let q = try NodeAsyncQueue(label: "NAPI_SWIFT_EXECUTOR")
        Self.defaultQueue = q
        return q
    }
}

// An object context that manages allocations in native code.
// You **must not** allow NodeContext instances to escape
// the scope in which they were called.
final class NodeContext {
    let environment: NodeEnvironment
    let isManaged: Bool

    private init(environment: NodeEnvironment, isManaged: Bool) {
        self.environment = environment
        self.isManaged = isManaged
    }

    // a list of values created with this context
    private var values: [Weak<NodeValueBase>] = []
    func registerValue(_ value: NodeValueBase) {
        // if we're in debug mode, register the value even in
        // unmanaged mode, to allow us to do sanity checks
        #if !DEBUG
        guard isManaged else { return }
        #endif
        values.append(Weak(value))
    }

    @NodeActor private static func _withContext<T>(
        _ ctx: NodeContext,
        environment env: NodeEnvironment,
        isTopLevel: Bool,
        do action: @NodeActor (NodeContext) throws -> T
    ) throws -> T {
        let ret: T
        do {
            ret = try action(ctx)
            if isTopLevel {
                // get the release queue one time and pass it in
                // to all persist calls for perf
                let q = try env.getDefaultQueue()
                for val in ctx.values {
                    try val.value?.persist(releaseQueue: q)
                }
                ctx.values.removeAll()
            } else {
                #if DEBUG
                let escapedBase: NodeValueBase?
                #endif
                // this allows for the escaping of a single NodeValue
                // from a non-toplevel context
                if let escapedRet = ret as? NodeValue {
                    let base = escapedRet.base
                    try base.persist()
                    #if DEBUG
                    escapedBase = base
                    #endif
                } else {
                    #if DEBUG
                    escapedBase = nil
                    #endif
                }
                #if DEBUG
                // if anything besides the return value of `action` escaped, it's
                // an error on the user's end
                if let escaped = ctx.values.lazy.compactMap({ $0.value }).filter({ $0 !== escapedBase }).first {
                    nodeFatalError("\(escaped) escaped unmanaged NodeContext")
                }
                #endif
            }
        } catch let error where isTopLevel {
            try? ctx.environment.throw(error)
            // we have to bail before the return statement somehow.
            // isTopLevel:true is accompanied by try? so what we
            // throw here doesn't really matter
            throw error
        }
        return ret
    }

    @NodeActor private static func withContext<T>(
        environment env: NodeEnvironment,
        isTopLevel: Bool,
        do action: @NodeActor (NodeContext) throws -> T
    ) throws -> T {
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
            node_swift_context_push(Unmanaged.passUnretained(ctx).toOpaque())
            defer { node_swift_context_pop() }
            #if DEBUG
            defer { weakCtx = ctx }
            #endif
            if isTopLevel, #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                let q = try env.getDefaultQueue()
                return try NodeActor.$target.withValue(q.handle()) {
                    return try _withContext(ctx, environment: env, isTopLevel: isTopLevel, do: action)
                }
            } else {
                return try _withContext(ctx, environment: env, isTopLevel: isTopLevel, do: action)
            }
        }
    }

    static func withUnsafeEntrypoint<T>(_ raw: napi_env, action: @NodeActor @Sendable (NodeContext) throws -> T) -> T? {
        withUnsafeEntrypoint(NodeEnvironment(raw), action: action)
    }

    static func withUnsafeEntrypoint<T>(_ environment: NodeEnvironment, action: @NodeActor @Sendable (NodeContext) throws -> T) -> T? {
        NodeActor.unsafeAssumeIsolated {
            try? withContext(environment: environment, isTopLevel: true, do: action)
        }
    }

    // This should be called at any entrypoint into our code from JS, with the
    // passed in environment.
    //
    // Upon completion of `action`, we can persist any node values that were
    // escaped, and perform other necessary cleanup.
    @NodeActor static func withContext<T>(environment: NodeEnvironment, do action: @NodeActor (NodeContext) throws -> T) -> T? {
        try? withContext(environment: environment, isTopLevel: true, do: action)
    }

    // Calls `action` with a NodeContext which does not manage NodeValueConvertible
    // instances created using it. That is, the new context will assume that all
    // NodeValueConvertible instances created with it (except for possibly the return value)
    // do not escape its own lifetime, which in turn is exactly the lifetime of the closure.
    // This trades away safety for performance.
    //
    // Note that this is a dangerous API to use. The cause of UB could be as innocuous as
    // calling NodeClass.constructor(), which memoizes (and thereby escapes) the returned
    // NodeFunction. Even something as trivial as calling NodeValueConvertible.rawValue()
    // could thus yield UB, eg if the receiver is `NodeDeferredValue { MyClass.constructor() }`
    @NodeActor static func withUnmanagedContext<T>(environment: NodeEnvironment, do action: @NodeActor (NodeContext) throws -> T) throws -> T {
        try withContext(environment: environment, isTopLevel: false, do: action)
    }

    static var hasCurrent: Bool {
        node_swift_context_peek() != nil
    }

    static var current: NodeContext {
        guard let last = node_swift_context_peek() else {
            // Node doesn't give us a backtrace (because we're not on a JS thread?) so
            // print one ourselves
            print(Thread.callStackSymbols.joined(separator: "\n"))
            nodeFatalError("Attempted to call a NodeAPI function on a non-JS thread")
        }
        return Unmanaged.fromOpaque(last).takeUnretainedValue()
    }
}

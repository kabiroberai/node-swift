import CNodeAPI

// similar to Combine.Future
public final class NodePromise: NodeObject {
    public enum Error: Swift.Error {
        case completedTwice
    }

    // similar to Combine.Promise
    public final class Deferred {
        public private(set) var hasCompleted = false
        public let promise: NodePromise
        var raw: napi_deferred

        public init() throws {
            let ctx = NodeContext.current
            var value: napi_value!
            var deferred: napi_deferred!
            try ctx.environment.check(napi_create_promise(ctx.environment.raw, &deferred, &value))
            self.promise = NodePromise(NodeValueBase(raw: value, in: ctx))
            self.raw = deferred
        }

        public func callAsFunction(_ result: Result<NodeValueConvertible, Swift.Error>) throws {
            // calling reject/resolve multiple times is considered UB
            // by Node
            guard !hasCompleted else {
                throw Error.completedTwice
            }
            let env = promise.base.environment
            switch result {
            case .success(let value):
                try env.check(napi_resolve_deferred(env.raw, raw, value.rawValue()))
            case .failure(let error):
                try env.check(napi_reject_deferred(env.raw, raw, NodeException(error: error).value.rawValue()))
            }
            hasCompleted = true
        }

        @_disfavoredOverload
        public func callAsFunction(_ result: Result<Void, Swift.Error>) throws {
            switch result {
            case .success:
                try self(.success(NodeUndefined()))
            case .failure(let error):
                try self(.failure(error))
            }
        }
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init(executor: (_ deferred: Deferred) -> Void) throws {
        let deferred = try Deferred()
        executor(deferred)
        super.init(deferred.promise.base)
    }

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_promise(env.raw, value.rawValue(), &result))
        return result
    }

}

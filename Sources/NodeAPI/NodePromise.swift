import CNodeAPI

// similar to Combine.Future
public final class NodePromise: NodeObject {

    // similar to Combine.Promise
    public final class Deferred {
        public enum Error: Swift.Error {
            case promiseFinishedTwice
        }

        public private(set) var hasFinished = false
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

        // calling reject/resolve multiple times is considered UB
        // by Node

        public func resolve(with resolution: NodeValueConvertible) throws {
            guard !hasFinished else {
                throw Error.promiseFinishedTwice
            }
            let env = promise.base.environment
            try env.check(napi_resolve_deferred(env.raw, raw, resolution.rawValue()))
            hasFinished = true
        }

        public func reject(with rejection: NodeValueConvertible) throws {
            guard !hasFinished else {
                throw Error.promiseFinishedTwice
            }
            let env = promise.base.environment
            try env.check(napi_reject_deferred(env.raw, raw, rejection.rawValue()))
            hasFinished = true
        }
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    // TODO: Align with Combine.Future.init: pass an escaping Result-taking closure
    // (and make Deferred private)
    public init(executor: (_ deferred: Deferred) throws -> Void) throws {
        let deferred = try Deferred()
        do {
            try executor(deferred)
        } catch {
            try deferred.reject(with: NodeError(code: "\(Swift.type(of: error))", message: "\(error)"))
        }
        super.init(deferred.promise.base)
    }

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_promise(env.raw, value.rawValue(), &result))
        return result
    }

}

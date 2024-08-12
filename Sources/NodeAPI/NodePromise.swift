@_implementationOnly import CNodeAPI

// similar to Combine.Future
public final class NodePromise: NodeObject {
    public enum Error: Swift.Error {
        case completedTwice
    }

    // similar to Combine.Promise
    @NodeActor public final class Deferred {
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
                try env.check(napi_reject_deferred(env.raw, raw, AnyNodeValue(error: error).rawValue()))
            }
            hasCompleted = true
        }

        @_disfavoredOverload
        public func callAsFunction(_ result: Result<Void, Swift.Error>) throws {
            switch result {
            case .success:
                try self(.success(undefined))
            case .failure(let error):
                try self(.failure(error))
            }
        }
    }

    @_spi(NodeAPI) public required init(_ base: NodeValueBase) {
        super.init(base)
    }

    public init(body: (_ deferred: Deferred) -> Void) throws {
        let deferred = try Deferred()
        body(deferred)
        super.init(deferred.promise.base)
    }

    override class func isObjectType(for value: NodeValueBase) throws -> Bool {
        let env = value.environment
        var result = false
        try env.check(napi_is_promise(env.raw, value.rawValue(), &result))
        return result
    }

    // sugar around then/catch
    public func get(completion: @escaping (Result<AnyNodeValue, Swift.Error>) -> Void) {
        // since we're on NodeActor, access to hasResumed is serial
        var hasResumed = false
        do {
            try self.then(NodeFunction { (val: AnyNodeValue) in
                if !hasResumed {
                    hasResumed = true
                    completion(.success(val))
                }
                return undefined
            }).catch(NodeFunction { (err: AnyNodeValue) in
                if !hasResumed {
                    hasResumed = true
                    completion(.failure(err))
                }
                return undefined
            })
        } catch {
            if !hasResumed {
                hasResumed = true
                completion(.failure(error))
            }
        }
    }

}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NodePromise {

    public convenience init(body: @escaping @Sendable @NodeActor () async throws -> NodeValueConvertible) throws {
        try self.init { deferred in
            Task {
                let result: Result<NodeValueConvertible, Swift.Error>
                do {
                    result = .success(try await body())
                } catch {
                    result = .failure(error)
                }
                try deferred(result)
            }
        }
    }

    public var value: AnyNodeValue {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.get { continuation.resume(with: $0) }
            }
        }
    }

}

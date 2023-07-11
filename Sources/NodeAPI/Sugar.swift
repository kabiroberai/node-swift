extension NodeFunction {

    public convenience init<each A: AnyNodeValueCreatable>(
        name: String = "",
        callback: @escaping @NodeActor (repeat each A) throws -> NodeValueConvertible
    ) throws {
        try self.init(name: name) { args in
            var i = 0
            return try callback(repeat args[i++] as (each A))
        }
    }

    public convenience init<each A: AnyNodeValueCreatable>(
        name: String = "",
        callback: @escaping @NodeActor (repeat each A) async throws -> NodeValueConvertible
    ) throws {
        try self.init(name: name) { args in
            var i = 0
            return try await callback(repeat args[i++] as (each A))
        }
    }

}

extension NodeMethod {

    #warning("TODO: swiftc currently crashes when implementing these")

    public init<T: NodeClass, each A: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (repeat each A) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                fatalError("Cannot implement yet due to a compiler bug")
//                var i = 0
//                return try callback(target)(repeat args[i++] as (each A))
            }
        }
    }

    public init<T: NodeClass, each A: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (repeat each A) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                try NodePromise {
                    fatalError("Cannot implement yet due to a compiler bug")
//                    var i = 0
//                    return try await callback(target)(repeat args[i++] as (each A))
                }
            }
        }
    }

}

extension NodeConstructor {
    public init<each A: AnyNodeValueCreatable>(
        _ invoke: @escaping @NodeActor (repeat each A) throws -> T
    ) {
        self.init { args in
            var i = 0
            return try invoke(repeat (each A).from(args[i++])!)
        }
    }
}

// return of the king
private postfix func ++(value: inout Int) -> Int {
    let old = value
    value += 1
    return old
}

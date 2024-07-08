extension NodeFunction {

    public convenience init<each A: AnyNodeValueCreatable>(
        name: String = "",
        callback: @escaping @NodeActor (repeat each A) throws -> NodeValueConvertible
    ) throws {
        try self.init(name: name) { args in
            var reader = ArgReader(args)
            return try callback(repeat reader.next() as each A)
        }
    }

    public convenience init<each A: AnyNodeValueCreatable>(
        name: String = "",
        callback: @escaping @NodeActor (repeat each A) throws -> Void
    ) throws {
        try self.init(name: name) { args in
            var reader = ArgReader(args)
            return try callback(repeat reader.next() as each A)
        }
    }

    public convenience init<each A: AnyNodeValueCreatable>(
        name: String = "",
        callback: @escaping @NodeActor (repeat each A) async throws -> NodeValueConvertible
    ) throws {
        try self.init(name: name) { args in
            var reader = ArgReader(args)
            return try await callback(repeat reader.next() as each A)
        }
    }

    public convenience init<each A: AnyNodeValueCreatable>(
        name: String = "",
        callback: @escaping @NodeActor (repeat each A) async throws -> Void
    ) throws {
        try self.init(name: name) { args in
            var reader = ArgReader(args)
            return try await callback(repeat reader.next() as each A)
        }
    }

}

extension NodeMethod {

    // instance methods

    public init<T: NodeClass, each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (repeat each A) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                var reader = ArgReader(args)
                return try callback(target)(repeat reader.next() as each A)
            }
        }
    }

    public init<T: NodeClass, each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (repeat each A) throws -> Void
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                var reader = ArgReader(args)
                return try callback(target)(repeat reader.next() as each A)
            }
        }
    }

    public init<T: NodeClass, each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (repeat each A) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                var reader = ArgReader(args)
                return try await callback(target)(repeat reader.next() as each A)
            }
        }
    }

    public init<T: NodeClass, each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (repeat each A) async throws -> Void
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                var reader = ArgReader(args)
                return try await callback(target)(repeat reader.next() as each A)
            }
        }
    }

    // static methods

    public init<each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping @NodeActor (repeat each A) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes.union(.static)) { (args: NodeArguments) in
            var reader = ArgReader(args)
            return try callback(repeat reader.next() as each A)
        }
    }

    public init<each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping @NodeActor (repeat each A) throws -> Void
    ) {
        self.init(attributes: attributes.union(.static)) { (args: NodeArguments) in
            var reader = ArgReader(args)
            return try callback(repeat reader.next() as each A)
        }
    }

    public init<each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping @NodeActor (repeat each A) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes.union(.static)) { (args: NodeArguments) in
            var reader = ArgReader(args)
            return try await callback(repeat reader.next() as each A)
        }
    }

    public init<each A: AnyNodeValueCreatable>(
        attributes: NodePropertyAttributes = .defaultMethod,
        _ callback: @escaping @NodeActor (repeat each A) async throws -> Void
    ) {
        self.init(attributes: attributes.union(.static)) { (args: NodeArguments) in
            var reader = ArgReader(args)
            return try await callback(repeat reader.next() as each A)
        }
    }

}

extension NodeConstructor {
    public init<each A: AnyNodeValueCreatable>(
        _ invoke: @escaping @NodeActor @Sendable (repeat each A) throws -> T
    ) {
        self.init { args in
            var reader = ArgReader(args)
            return try invoke(repeat reader.next() as (each A))
        }
    }
}

@NodeActor private struct ArgReader {
    var index = 0
    let arguments: NodeArguments
    init(_ arguments: NodeArguments) {
        self.arguments = arguments
    }
    mutating func next<T: AnyNodeValueCreatable>() throws -> T {
        defer { index += 1 }
        if index < arguments.count {
            guard let converted = try arguments[index].as(T.self) else {
                throw try NodeError(
                    code: nil,
                    message: "Could not convert parameter \(index) to type \(T.self)"
                )
            }
            return converted
        } else {
            // if we're asking for an arg that's out of bounds,
            // return the equivalent of `undefined` if possible,
            // else throw
            guard let converted = try undefined.as(T.self) else {
                throw try NodeError(
                    code: nil,
                    message: "At least \(index + 1) argument\(index == 0 ? "" : "s") required. Got \(arguments.count)."
                )
            }
            return converted
        }
    }
}

extension NodeClass {
    // used to refer to Self as a non-covariant
    @_documentation(visibility: private)
    public typealias _NodeSelf = Self
}

@attached(extension, conformances: NodeClass, names: named(properties), named(construct))
public macro NodeClass() = #externalMacro(module: "NodeAPIMacros", type: "NodeClassMacro")

@attached(peer, names: named(construct))
public macro NodeConstructor() = #externalMacro(module: "NodeAPIMacros", type: "NodeConstructorMacro")

@attached(peer, names: prefixed(`$`))
public macro NodeMethod(_: NodePropertyAttributes = .defaultMethod)
    = #externalMacro(module: "NodeAPIMacros", type: "NodeMethodMacro")

@attached(peer, names: prefixed(`$`))
public macro NodeProperty(_: NodePropertyAttributes = .defaultProperty)
    = #externalMacro(module: "NodeAPIMacros", type: "NodePropertyMacro")

@attached(peer, names: prefixed(`$`))
public macro NodeName(_: NodeName)
    = #externalMacro(module: "NodeAPIMacros", type: "NodeNameMacro")

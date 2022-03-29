// Automatically Generated From Sugar.swift.gyb.
// Do Not Edit Directly!

// Instead, edit Sugar.swift.gyb and then `npm run gyb`

extension NodeFunction {

    public convenience init(name: String = "", callback: @escaping @NodeActor () throws -> NodeValueConvertible) throws {
        try self.init(name: name) { _ in
            try callback()
        }
    }

    public convenience init<A0: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6], $0[7])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6], $0[7], $0[8])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable, A9: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8, A9) throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6], $0[7], $0[8], $0[9])
        }
    }

}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NodeFunction {

    public convenience init(name: String = "", callback: @escaping @NodeActor () async throws -> NodeValueConvertible) throws {
        try self.init(name: name) { _ in
            try await callback()
        }
    }

    public convenience init<A0: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2], $0[3])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2], $0[3], $0[4])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6], $0[7])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6], $0[7], $0[8])
        }
    }

    public convenience init<A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable, A9: AnyNodeValueCreatable>(name: String = "", callback: @escaping @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8, A9) async throws -> NodeValueConvertible) throws {
        try self.init(name: name) {
            try await callback($0[0], $0[1], $0[2], $0[3], $0[4], $0[5], $0[6], $0[7], $0[8], $0[9])
        }
    }

}

extension NodeMethod {

    private init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T, NodeArguments) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                try callback(target, args)
            }
        }
    }

    public init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor () throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { target, _ in try callback(target)() }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2], $1[3]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6], $1[7]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6], $1[7], $1[8]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable, A9: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8, A9) throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6], $1[7], $1[8], $1[9]
        ) }
    }

}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NodeMethod {

    private init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T, NodeArguments) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { (target: T) in
            { (args: NodeArguments) in
                try NodePromise {
                    try await callback(target, args)
                }
            }
        }
    }

    public init<T: NodeClass>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor () async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { target, _ in try await callback(target)() }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2], $1[3]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6], $1[7]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6], $1[7], $1[8]
        ) }
    }

    public init<T: NodeClass, A0: AnyNodeValueCreatable, A1: AnyNodeValueCreatable, A2: AnyNodeValueCreatable, A3: AnyNodeValueCreatable, A4: AnyNodeValueCreatable, A5: AnyNodeValueCreatable, A6: AnyNodeValueCreatable, A7: AnyNodeValueCreatable, A8: AnyNodeValueCreatable, A9: AnyNodeValueCreatable>(
        attributes: NodeProperty.Attributes = .defaultMethod,
        _ callback: @escaping (T) -> @NodeActor (A0, A1, A2, A3, A4, A5, A6, A7, A8, A9) async throws -> NodeValueConvertible
    ) {
        self.init(attributes: attributes) { try await callback($0)(
            $1[0], $1[1], $1[2], $1[3], $1[4], $1[5], $1[6], $1[7], $1[8], $1[9]
        ) }
    }

}

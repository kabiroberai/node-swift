extension Sequence where Element: NodeValueConvertible {
    @NodeActor public func nodeIterator() -> NodeIterator {
        NodeIterator(self.lazy.map { $0 as NodeValueConvertible }.makeIterator())
    }
}

public final class NodeIterator: NodeClass {
    public struct Result: NodeValueConvertible, NodeValueCreatable {
        public typealias ValueType = NodeObject

        let value: NodeValueConvertible?
        let done: Bool?

        public func nodeValue() throws -> any NodeValue {
            let obj = try NodeObject()
            if let value = value {
                try obj["value"].set(to: value)
            }
            if let done = done {
                try obj["done"].set(to: done)
            }
            return obj
        }

        public static func from(_ value: ValueType) throws -> Self {
            Self(
                value: try value.get("value"),
                done: try value.get("done").as(Bool.self)
            )
        }
    }

    public static let properties: NodeClassPropertyList = [
        "next": NodeMethod(next),
    ]

    private var iterator: any IteratorProtocol<NodeValueConvertible>
    public init(_ iterator: any IteratorProtocol<NodeValueConvertible>) {
        self.iterator = iterator
    }

    public func next() -> Result {
      if let value = iterator.next() {
        return Result(value: value, done: false)
      } else {
        return Result(value: nil, done: true)
      }
    }
}


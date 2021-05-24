import CNodeAPI

public protocol NodeExceptionConvertible: Error {
    var exception: NodeValue { get }
}

public struct NodeException: NodeExceptionConvertible {
    public let exception: NodeValue
    public init(_ exception: NodeValue) {
        self.exception = exception
    }
}

public func nodeFatalError(_ message: String = "", file: StaticString = #file, line: UInt = #line) -> Never {
    var message = message
    message.withUTF8 {
        $0.withMemoryRebound(to: CChar.self) { messageBuf -> Never in
            var loc = "\(file):\(line)"
            loc.withUTF8 {
                $0.withMemoryRebound(to: CChar.self) { locBuf in
                    napi_fatal_error(locBuf.baseAddress, locBuf.count, messageBuf.baseAddress, messageBuf.count)
                }
            }
        }
    }
}

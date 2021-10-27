@_implementationOnly import CNodeAPI

public protocol NodeExceptionConvertible: Error {
    func exceptionValue() throws -> NodeValue
}

public struct NodeException: NodeExceptionConvertible {
    public func exceptionValue() throws -> NodeValue { value }

    public let value: NodeValue
    public init(value: NodeValue) {
        self.value = value
    }

    public init(error: Error) throws {
        switch error {
        case let error as NodeExceptionConvertible:
            // if it's already NodeExceptionConvertible, use that
            // exception value
            self.value = try error.exceptionValue()
        // TODO: handle specific error types
//        case let error as NodeAPIError:
//            break
//        case let error where type(of: error) is NSError.Type:
//            let cocoaError = error as NSError
//            break
        // TODO: maybe create our own Error class which allows round-tripping the
        // actual error object, instead of merely passing along stringified vals
        case let error:
            self.value = try NodeError(code: "\(type(of: error))", message: "\(error)")
        }
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

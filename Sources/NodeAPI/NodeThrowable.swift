@_implementationOnly import CNodeAPI

extension AnyNodeValue {
    private static let exceptionKey = NodeWrappedDataKey<Error>()

    public init(error: Error) throws {
        switch error {
        case let error as NodeValue:
            // if it's already a NodeValue, assign the base directly
            self.init(error)
        // TODO: handle specific error types
//        case let error as NodeAPIError:
//            break
//        case let error where type(of: error) is NSError.Type:
//            let cocoaError = error as NSError
//            break
        // TODO: maybe create our own Error class which allows round-tripping the
        // actual error object, instead of merely passing along stringified vals
        case let error:
            let nodeError = try NodeError(code: "\(type(of: error))", message: "\(error)")
            try nodeError.setWrappedValue(error, forKey: Self.exceptionKey)
            self.init(nodeError)
        }
    }

    public var nativeError: Error? {
        try? self.as(NodeError.self)?.wrappedValue(forKey: Self.exceptionKey)
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

@_implementationOnly import CNodeAPI
import Foundation

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

public func nodeFatalError(_ message: String = "", file: StaticString = #fileID, line: UInt = #line) -> Never {
    print("nodeFatalError: dumping call stack\n\(Thread.callStackSymbols.joined(separator: "\n"))")
    let loc = "\(file):\(line)"
    napi_fatal_error(loc, loc.utf8.count, message, message.utf8.count)
}

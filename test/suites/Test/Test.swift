import Foundation
import NodeAPI

final class File: NodeClass {
    static let properties: NodeClassPropertyList = [
        "contents": NodeProperty(get: contents, set: setContents),
        "unlink": NodeMethod(unlink),
        "default": NodeMethod(attributes: .static, `default`),
        "filename": NodeProperty(get: filename),
        "reply": NodeMethod(reply),
        "x": NodeProperty(\File.x),
    ]

    nonisolated(unsafe) var x: Int = 0

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(_ args: NodeArguments) throws {
        guard let path = try args[0].as(String.self) else {
            throw try NodeError(
                typeErrorCode: "ERR_INVALID_ARG_TYPE",
                message: "Expected string"
            )
        }
        url = URL(fileURLWithPath: path)
    }

    static let construct = NodeConstructor(File.init(_:))

    static func `default`(_ args: NodeArguments) throws -> NodeValueConvertible {
        return try File(url: URL(fileURLWithPath: "default.txt")).wrapped()
    }

    func filename() throws -> String {
        url.lastPathComponent
    }

    func contents() throws -> Data {
        try Data(contentsOf: url)
    }

    func setContents(_ newValue: Data) throws {
        try newValue.write(to: url, options: .atomic)
    }

    // unrelated to files but an important test nonetheless
    func reply(_ parameter: String?) -> String {
        "You said \(parameter ?? "nothing")"
    }

    func unlink() throws -> NodeValueConvertible {
        try FileManager.default.removeItem(at: url)
        return undefined
    }
}

final class SomeIterable: NodeClass {
    typealias Element = String
  
    static let properties: NodeClassPropertyList = [
        NodeSymbol.iterator: NodeMethod(nodeIterator),
    ]

    static let construct = NodeConstructor(SomeIterable.init(_:))
    init(_ args: NodeArguments) throws { }

    private let values: [String] = ["one", "two", "three"]
  
    func nodeIterator() throws -> NodeIterator {
        values.nodeIterator()
    }

}

#NodeModule(exports: ["File": File.deferredConstructor, "SomeIterable": SomeIterable.deferredConstructor])

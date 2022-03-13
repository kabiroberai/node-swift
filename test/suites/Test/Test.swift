import Foundation
import NodeAPI

final class File: NodeClass {
    static let properties: NodeClassPropertyList = [
        "contents": NodeComputedProperty(get: contents, set: setContents),
        "unlink": NodeMethod(unlink),
        "default": NodeMethod(attributes: .static, `default`),
        "filename": NodeComputedProperty(get: filename),
        "reply": NodeMethod(reply)
    ]

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(_ args: NodeFunction.Arguments) throws {
        guard let path = try args[0].as(String.self) else {
            throw try NodeError(
                typeErrorCode: "ERR_INVALID_ARG_TYPE",
                message: "Expected string"
            )
        }
        url = URL(fileURLWithPath: path)
    }

    static func `default`(_ args: NodeFunction.Arguments) throws -> NodeValueConvertible {
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
        return NodeUndefined.deferred
    }
}

@main struct Test: NodeModule {
    let exports: NodeValueConvertible = ["File": File.deferredConstructor]
}

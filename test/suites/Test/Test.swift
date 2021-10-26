import Foundation
import NodeAPI

final class File: NodeClass {
    static let properties: NodeClassPropertyList = [
        "contents": NodeComputedProperty(get: contents, set: setContents),
        "unlink": NodeMethod(unlink)
    ]

    let url: URL
    init(_ args: NodeFunction.Arguments) throws {
        guard let path = try args[0].as(String.self) else {
            throw try NodeError(
                typeErrorCode: "ERR_INVALID_ARG_TYPE",
                message: "Expected string"
            )
        }
        url = URL(fileURLWithPath: path)
    }

    func contents() throws -> Data {
        try Data(contentsOf: url)
    }

    func setContents(_ newValue: Data) throws {
        try newValue.write(to: url, options: .atomic)
    }

    func unlink() throws -> NodeValueConvertible {
        try FileManager.default.removeItem(at: url)
        return NodeUndefined.deferred
    }
}

@main struct Test: NodeModule {
    let exports: NodeValueConvertible = ["File": File.deferredConstructor]
}

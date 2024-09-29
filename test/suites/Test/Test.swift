import Foundation
import NodeAPI

@NodeClass @NodeActor final class File {
    static let extraProperties: NodeClassPropertyList = [
        "contents": NodeProperty(
            of: File.self,
            get: { $0.contents },
            set: { $0.setContents }
        ),
        "filename": NodeProperty(
            of: File.self,
            get: { $0.filename }
        ),
    ]

    @NodeProperty
    var x: Int = 0

    let url: URL

    init(url: URL) {
        self.url = url
    }

    @NodeConstructor
    init(_ path: String) {
        url = URL(fileURLWithPath: path)
    }

    @NodeMethod
    static func `default`() throws -> NodeValueConvertible {
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
    @NodeMethod
    func reply(_ parameter: String?) -> String {
        "You said \(parameter ?? "nothing")"
    }

    @NodeMethod
    func unlink() throws -> NodeValueConvertible {
        try FileManager.default.removeItem(at: url)
        return undefined
    }
}

#NodeModule(exports: ["File": File.deferredConstructor])

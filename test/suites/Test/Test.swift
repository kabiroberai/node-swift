import Foundation
import NodeAPI

@main struct Test: NodeModule {
    var exports: NodeValueConvertible

    init() throws {
        let fileKey = NodeWrappedDataKey<URL>()
        exports = [
            "File": try NodeFunction(
                className: "File",
                properties: [
                    "contents": NodeComputedProperty { args in
                        let url = try args.this!.wrappedValue(forKey: fileKey)!
                        return try Data(contentsOf: url)
                    } set: { args in
                        let url = try args.this!.wrappedValue(forKey: fileKey)!
                        guard let newFile = try args[0].as(
                            NodeTypedArray<UInt8>.self
                        ) else {
                            throw try NodeError(
                                typeErrorCode: "ERR_INVALID_ARG_TYPE",
                                message: "Expected Buffer or Uint8Array"
                            )
                        }
                        try newFile.withUnsafeMutableBytes(Data.init(buffer:))
                            .write(to: url, options: .atomic)
                        return try NodeUndefined()
                    },
                    "unlink": NodeMethod { info in
                        let url = try info.this!.wrappedValue(forKey: fileKey)!
                        try FileManager.default.removeItem(at: url)
                        return try NodeUndefined()
                    }
                ]
            ) { args in
                guard let path = try args[0].as(NodeString.self) else {
                    throw try NodeError(
                        typeErrorCode: "ERR_INVALID_ARG_TYPE",
                        message: "Expected string"
                    )
                }
                let url = URL(fileURLWithPath: try path.string())
                try args.this!.setWrappedValue(url, forKey: fileKey)
                return try NodeUndefined()
            }
        ]
    }
}

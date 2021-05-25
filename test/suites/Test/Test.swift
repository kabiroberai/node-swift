import Foundation
import NodeAPI

@main struct Test: NodeModule {
    var exports: NodeValueConvertible

    init(context: NodeContext) throws {
        let fileKey = NodeWrappedDataKey<URL>()
        exports = [
            "File": try context.defineClass(
                name: "File",
                constructor: { ctx, info in
                    guard let path = try info.arguments[0].as(NodeString.self) else {
                        throw try NodeError(typeErrorCode: "ERR_INVALID_ARG_TYPE", message: "Expected string", in: ctx)
                    }
                    let url = URL(fileURLWithPath: try path.string())
                    try info.this!.setWrappedValue(url, forKey: fileKey)
                    return try NodeUndefined(in: ctx)
                }, properties: [
                    NodePropertyDescriptor(
                        name: "contents",
                        attributes: .defaultProperty,
                        value: .computed { ctx, info in
                            let url = try info.this!.wrappedValue(forKey: fileKey)!
                            return try Data(contentsOf: url)
                        } set: { ctx, info in
                            let url = try info.this!.wrappedValue(forKey: fileKey)!
                            guard let newFile = try info.arguments[0].as(NodeBuffer.self) else {
                                throw try NodeError(typeErrorCode: "ERR_INVALID_ARG_TYPE", message: "Expected buffer", in: ctx)
                            }
                            try newFile.withUnsafeMutableBytes(Data.init(_:)).write(to: url, options: .atomic)
                            return try NodeUndefined(in: ctx)
                        }
                    ),
                    NodePropertyDescriptor(
                        name: "unlink",
                        attributes: .defaultMethod,
                        value: .method { ctx, info in
                            let url = try info.this!.wrappedValue(forKey: fileKey)!
                            try FileManager.default.removeItem(at: url)
                            return try NodeUndefined(in: ctx)
                        }
                    )
                ]
            )
        ]
    }
}

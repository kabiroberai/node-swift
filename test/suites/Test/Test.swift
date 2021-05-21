import Foundation
import NodeAPI

@main struct Test: NodeModule {
    var exports: NodeValueConvertible

    init(context: NodeContext) throws {
        exports = [
            "readFile":
                try NodeFunction(in: context) { ctx, info in
                    try String(contentsOfFile: "\(info.arguments[0])")
                }
        ]
    }
}

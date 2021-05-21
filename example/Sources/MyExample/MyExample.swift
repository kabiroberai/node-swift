import NodeAPI

@main struct MyExample: NodeModule {
    var exports: NodeValueConvertible

    init(context: NodeContext) throws {
        exports = "Hello, world!"
    }
}

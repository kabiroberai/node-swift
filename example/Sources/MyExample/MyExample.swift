import NodeAPI

@main struct MyExample: NodeModule {
    let exports: NodeValueConvertible

    init(context: NodeContext) throws {
        exports = "Hello, world!"
    }
}

import NodeAPI

@main struct MyExample: NodeModule {
    let exports: NodeValueConvertible = "Hello, world!"
}

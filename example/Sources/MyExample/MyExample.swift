import NodeAPI

@main struct MyExample: NodeModule {
    let exports: NodeValueConvertible = [
        "nums": [Double.pi.rounded(.down), Double.pi.rounded(.up)],
        "str": String(repeating: "NodeSwift! ", count: 3),
        "add": try! NodeFunction { (a: Double, b: Double) in
            "\(a) + \(b) = \(a + b)"
        },
    ]
}

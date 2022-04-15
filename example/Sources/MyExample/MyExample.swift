import NodeAPI

@main struct MyExample: NodeModule {
    let exports: NodeValueConvertible
    init() throws {
        exports = try [
            "nums": [Double.pi.rounded(.down), Double.pi.rounded(.up)],
            "str": String(repeating: "NodeSwift! ", count: 3),
            "add": NodeFunction { (a: Double, b: Double) in
                print("calculating...")
                try await Task.sleep(nanoseconds: 500_000_000)
                return "\(a) + \(b) = \(a + b)"
            },
        ]
    }
}

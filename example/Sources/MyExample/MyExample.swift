import NodeAPI

#NodeModule(exports: [
    "nums": [Double.pi.rounded(.down), Double.pi.rounded(.up)],
    "str": String(repeating: "NodeSwift! ", count: 3),
    "add": try NodeFunction { (a: Double, b: Double) in
        print("calculating...")
        try await Task.sleep(nanoseconds: 500_000_000)
        return "\(a) + \(b) = \(a + b)"
    },
])

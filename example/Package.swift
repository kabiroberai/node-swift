// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "MyExample",
    products: [
        .library(
            name: "MyExample",
            targets: ["MyExample"]
        ),
    ],
    dependencies: [
        .package(path: "node_modules/node-swift")
    ],
    targets: [
        .target(
            name: "MyExample",
            dependencies: [
                .product(name: "NodeAPI", package: "node-swift")
            ]
        )
    ]
)

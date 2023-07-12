// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "MyExample",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "MyExample",
            targets: ["MyExample"]
        ),
        .library(
            name: "Module",
            type: .dynamic,
            targets: ["MyExample"]
        )
    ],
    dependencies: [
        .package(path: "node_modules/node-swift")
    ],
    targets: [
        .target(
            name: "MyExample",
            dependencies: [
                .product(name: "NodeAPI", package: "node-swift"),
                .product(name: "NodeModuleSupport", package: "node-swift"),
            ]
        )
    ]
)

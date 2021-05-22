// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "node-swift",
    products: [
        .library(
            name: "NodeAPI",
            targets: ["NodeAPI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(name: "CNodeAPI"),
        .target(
            name: "NodeAPI",
            dependencies: ["CNodeAPI"]
        )
    ]
)

// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "MyExample",
    products: [
        .library(
            name: "MyExample",
            type: .dynamic,
            targets: ["MyExample"]
        )
    ],
    dependencies: [
        .package(name: "NodeAPI", path: "node_modules/npm-build-swift")
    ],
    targets: [
        .target(
            name: "MyExample",
            dependencies: ["NodeAPI"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup"
                ])
            ]
        )
    ]
)

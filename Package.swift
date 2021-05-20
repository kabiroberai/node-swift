// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "NodeAPI",
    products: [
        .library(
            name: "NativeStuff",
            type: .dynamic,
            targets: ["NativeStuff"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(name: "CNodeAPI"),
        .target(
            name: "NodeAPI",
            dependencies: ["CNodeAPI"]
        ),
        .target(
            name: "NativeStuff",
            dependencies: ["NodeAPI"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"])
            ]
        ),
    ]
)

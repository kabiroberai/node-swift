// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "NativeStuff",
    products: [
        .library(
            name: "NativeStuff",
            type: .dynamic,
            targets: ["NativeStuff"]
        ),
    ],
    dependencies: [],
    targets: [
        // TODO: Rename to NodeAPI?
        .target(name: "CNAPI"),
        .target(
            name: "NAPIC",
            dependencies: ["CNAPI"]
        ),
        .target(
            name: "NAPI",
            dependencies: ["CNAPI", "NAPIC"]
        ),
        .target(
            name: "NativeStuff",
            dependencies: ["NAPI"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"])]
        ),
        .testTarget(
            name: "NativeStuffTests",
            dependencies: ["NativeStuff"]
        ),
    ]
)

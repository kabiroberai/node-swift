// swift-tools-version:5.3

import PackageDescription
import Foundation

let buildDynamic = ProcessInfo.processInfo.environment["NODE_SWIFT_BUILD_DYNAMIC"] == "1"

let package = Package(
    name: "node-swift",
    products: [
        .library(
            name: "NodeAPI",
            type: buildDynamic ? .dynamic : nil,
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

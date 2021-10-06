// swift-tools-version:5.3

import PackageDescription
import Foundation

// true when we're invoked via node-swift
let isRealBuild = ProcessInfo.processInfo.environment["NODE_SWIFT_TARGET_PACKAGE"] != nil

let package = Package(
    name: "node-swift",
    products: [
        .library(
            name: "NodeAPI",
            type: isRealBuild ? .dynamic : nil,
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

// swift-tools-version:5.3

import PackageDescription
import Foundation

let targetPackage = ProcessInfo.processInfo.environment["NODE_SWIFT_TARGET_PACKAGE"]!
let targetPath = ProcessInfo.processInfo.environment["NODE_SWIFT_TARGET_PATH"]!
let targetName = ProcessInfo.processInfo.environment["NODE_SWIFT_TARGET_NAME"]!
let targetMacVersion = ProcessInfo.processInfo.environment["NODE_SWIFT_TARGET_MAC_VERSION"]!
let hostBinary = ProcessInfo.processInfo.environment["NODE_SWIFT_HOST_BINARY"]!

let package = Package(
    name: "node-swift-host",
    platforms: [.macOS(targetMacVersion)],
    products: [
        .library(
            name: "NodeSwiftHost",
            type: .dynamic,
            targets: ["NodeSwiftHost"]
        )
    ],
    dependencies: [
        .package(name: targetPackage, path: targetPath)
    ],
    targets: [
        .target(
            name: "NodeSwiftHost",
            dependencies: [
                .product(name: targetName, package: targetPackage)
            ],
            path: ".",
            cSettings: [
                .define("HOST_BINARY", to: "\"\(hostBinary)\"")
            ]
        )
    ]
)

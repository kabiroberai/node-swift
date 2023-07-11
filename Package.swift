// swift-tools-version:5.9

import PackageDescription
import Foundation

let buildDynamic = ProcessInfo.processInfo.environment["NODE_SWIFT_BUILD_DYNAMIC"] == "1"
let enableEvolution = ProcessInfo.processInfo.environment["NODE_SWIFT_ENABLE_EVOLUTION"] == "1"

let package = Package(
    name: "node-swift",
    platforms: [
        .macOS(.v10_15), .iOS(.v13),
    ],
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
            dependencies: ["CNodeAPI"],
            swiftSettings: (enableEvolution ? [
                .unsafeFlags(["-enable-library-evolution"])
            ] : [])
        ),
    ],
    cxxLanguageStandard: .cxx14
)

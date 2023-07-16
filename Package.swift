// swift-tools-version:5.9

import PackageDescription
import CompilerPluginSupport
import Foundation

let buildDynamic = ProcessInfo.processInfo.environment["NODE_SWIFT_BUILD_DYNAMIC"] == "1"
let enableEvolution = ProcessInfo.processInfo.environment["NODE_SWIFT_ENABLE_EVOLUTION"] == "1"

let baseSwiftSettings: [SwiftSetting] = [
//    .unsafeFlags(["-Xfrontend", "-warn-concurrency"])
]

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
        ),
        .library(
            name: "NodeModuleSupport",
            targets: ["NodeModuleSupport"]
        ),
        .plugin(
            name: "BuildNodeModule",
            targets: ["BuildNodeModule"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "release/5.9"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .target(name: "CNodeAPI"),
        .macro(
            name: "NodeAPIMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: baseSwiftSettings
        ),
        .target(
            name: "NodeAPI",
            dependencies: ["CNodeAPI", "NodeAPIMacros"],
            swiftSettings: baseSwiftSettings + (enableEvolution ? [
                .unsafeFlags(["-enable-library-evolution"])
            ] : [])
        ),
        .target(
            name: "NodeModuleSupport",
            dependencies: ["CNodeAPI"]
        ),
        .executableTarget(
            name: "BuildNodeModuleHelper",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .plugin(
            name: "BuildNodeModule",
            capability: .command(
                intent: .custom(verb: "module", description: "Build Node module"),
                permissions: [.writeToPackageDirectory(
                    reason: "To output your Node module."
                )]
            ),
            dependencies: ["BuildNodeModuleHelper"]
        ),
    ],
    cxxLanguageStandard: .cxx14
)

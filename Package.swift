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
            name: "NodeModules",
            targets: ["NodeModules"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "release/5.9"),
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
        .macro(
            name: "NodeModulesMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: baseSwiftSettings
        ),
        .target(
            name: "CNodeModules",
            dependencies: ["CNodeAPI"]
        ),
        .target(
            name: "NodeModules",
            dependencies: ["CNodeModules", "NodeAPI", "NodeModulesMacros"],
            swiftSettings: baseSwiftSettings
        ),
    ],
    cxxLanguageStandard: .cxx14
)

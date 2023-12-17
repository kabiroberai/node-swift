// swift-tools-version:5.9

import PackageDescription
import CompilerPluginSupport
import Foundation

let buildDynamic = ProcessInfo.processInfo.environment["NODE_SWIFT_BUILD_DYNAMIC"] == "1"

let baseSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
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
            name: "NodeJSC",
            targets: ["NodeJSC"]
        ),
        .library(
            name: "NodeModuleSupport",
            targets: ["NodeModuleSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        .systemLibrary(name: "CNodeAPI"),
        .target(
            name: "CNodeJSC",
            cSettings: [
                .define("NODE_ADDON_API_DISABLE_DEPRECATED"),
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore"),
            ]
        ),
        .target(
            name: "NodeJSC",
            dependencies: [
                "CNodeJSC",
                "NodeAPI",
            ]
        ),
        .target(name: "CNodeAPISupport"),
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
            dependencies: ["CNodeAPI", "CNodeAPISupport", "NodeAPIMacros"],
            cSettings: [.define("NAPI_VERSION", to: "7")],
            swiftSettings: baseSwiftSettings + [
                .define("NAPI_VERSIONED")
            ]
        ),
        .target(
            name: "NodeModuleSupport",
            dependencies: ["CNodeAPI"]
        ),
        .testTarget(
            name: "NodeJSCTests",
            dependencies: ["NodeJSC", "NodeAPI"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)

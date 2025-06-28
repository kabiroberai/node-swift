// swift-tools-version:6.0

import PackageDescription
import Foundation

// using ".." doesn't work on Windows. Also,
// relative paths work via the CLI but not with Xcode.
let testDir = URL(filePath: #filePath).deletingLastPathComponent()
let suites = testDir.appending(component: "suites")
let nodeSwiftPath = testDir.deletingLastPathComponent().path

let package = Package(
    name: "NodeAPITests",
    platforms: [.macOS("10.15")],
    dependencies: [.package(name: "node-swift", path: nodeSwiftPath)]
)

@MainActor func addSuite(_ suite: String) {
    package.products.append(.library(
        name: suite,
        type: .dynamic,
        targets: [suite]
    ))
    package.products.append(.library(
        name: "\(suite)-Automatic",
        targets: [suite]
    ))
    package.targets.append(.target(
        name: suite,
        dependencies: [
            .product(name: "NodeAPI", package: "node-swift"),
            .product(name: "NodeUV", package: "node-swift"),
            .product(name: "NodeModuleSupport", package: "node-swift"),
        ],
        path: "suites/\(suite)",
        exclude: ["index.js"],
        swiftSettings: [
            .unsafeFlags(["-Xfrontend", "-warn-concurrency"])
        ]
    ))
}

for suite in try FileManager.default.contentsOfDirectory(atPath: suites.path)
    where !suite.hasPrefix(".") {
    addSuite(suite)
}

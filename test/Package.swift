// swift-tools-version:5.3

import PackageDescription
import Foundation

// using ".." doesn't work on Windows
let nodeSwiftPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path

let package = Package(
    name: "NodeAPITests",
    dependencies: [.package(name: "node-swift", path: nodeSwiftPath)]
)

func addSuite(_ suite: String) {
    package.products.append(.library(
        name: suite,
        targets: [suite]
    ))
    package.targets.append(.target(
        name: suite,
        dependencies: [.product(name: "NodeAPI", package: "node-swift")],
        path: "suites/\(suite)",
        exclude: ["index.js"]
    ))
}

// relative paths work via the CLI but not with Xcode
let suites = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("suites")

for suite in try FileManager.default.contentsOfDirectory(atPath: suites.path)
    where !suite.hasPrefix(".") {
    addSuite(suite)
}

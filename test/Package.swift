// swift-tools-version:5.3

import PackageDescription
import Foundation

let package = Package(
    name: "NodeAPITests",
    dependencies: [.package(name: "NodeAPI", path: "..")]
)

func addSuite(_ suite: String) {
    package.products.append(.library(
        name: suite,
        type: .dynamic,
        targets: [suite]
    ))
    package.targets.append(.target(
        name: suite,
        dependencies: ["NodeAPI"],
        path: "suites/\(suite)",
        exclude: ["index.js"],
        linkerSettings: [
            .unsafeFlags([
                "-Xlinker", "-undefined",
                "-Xlinker", "dynamic_lookup"
            ])
        ]
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

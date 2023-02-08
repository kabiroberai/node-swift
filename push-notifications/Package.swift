// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "AmiePushNotifications",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "AmiePushNotifications",
            targets: ["AmiePushNotifications"]
        ),
    ],
    dependencies: [
        .package(path: "node_modules/node-swift")
    ],
    targets: [
        .target(
            name: "AmiePushNotifications",
            dependencies: [
                .product(name: "NodeAPI", package: "node-swift")
            ]
        )
    ]
)

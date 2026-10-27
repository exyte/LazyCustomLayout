// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LazyCustomLayout",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "LazyCustomLayout",
            targets: ["LazyCustomLayout"]),
    ],
    targets: [
        .target(
            name: "LazyCustomLayout",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LazyCustomLayoutTests",
            dependencies: ["LazyCustomLayout"]
        ),
    ]
)

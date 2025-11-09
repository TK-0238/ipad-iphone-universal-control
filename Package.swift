// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "iPadとiPhone連携操作",
    defaultLocalization: "ja",
    platforms: [
        .iOS("17.0"),
        .macOS("14.0")
    ],
    products: [
        .library(
            name: "SharedControlKit",
            targets: ["SharedControlKit"]
        ),
        .library(
            name: "SidecarCastingKit",
            targets: ["SidecarCastingKit"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SharedControlKit",
            path: "Sources/SharedControlKit"
        ),
        .target(
            name: "SidecarCastingKit",
            dependencies: ["SharedControlKit"],
            path: "Sources/SidecarCastingKit"
        ),
        .testTarget(
            name: "SharedControlKitTests",
            dependencies: ["SharedControlKit"],
            path: "Tests/SharedControlKitTests"
        )
    ]
)

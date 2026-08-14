// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArgusCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArgusSupport", targets: ["ArgusSupport"]),
        .library(name: "ArgusConfigKit", targets: ["ArgusConfigKit"]),
    ],
    targets: [
        .target(
            name: "ArgusSupport",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ArgusSupportTests",
            dependencies: ["ArgusSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ArgusConfigKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ArgusConfigKitTests",
            dependencies: ["ArgusConfigKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

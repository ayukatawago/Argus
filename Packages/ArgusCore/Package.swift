// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArgusCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArgusSupport", targets: ["ArgusSupport"])
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
    ]
)

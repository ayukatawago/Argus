// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiffReviewKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiffReviewKit", targets: ["DiffReviewKit"])
    ],
    targets: [
        .target(
            name: "DiffReviewKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DiffReviewKitTests",
            dependencies: ["DiffReviewKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

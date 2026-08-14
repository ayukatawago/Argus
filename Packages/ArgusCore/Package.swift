// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArgusCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArgusSupport", targets: ["ArgusSupport"]),
        .library(name: "ArgusConfigKit", targets: ["ArgusConfigKit"]),
        .library(name: "AgentStateKit", targets: ["AgentStateKit"]),
        .library(name: "Workspaces", targets: ["Workspaces"]),
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
        .target(
            name: "AgentStateKit",
            dependencies: ["ArgusSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AgentStateKitTests",
            dependencies: ["AgentStateKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Workspaces",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WorkspacesTests",
            dependencies: ["Workspaces"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

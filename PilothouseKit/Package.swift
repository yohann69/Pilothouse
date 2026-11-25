// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PilothouseKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PilothouseKit", targets: ["PilothouseKit"])
    ],
    targets: [
        .target(
            name: "PilothouseKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PilothouseKitTests",
            dependencies: ["PilothouseKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

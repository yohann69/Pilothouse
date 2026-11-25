// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArrcadeKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ArrcadeKit", targets: ["ArrcadeKit"])
    ],
    targets: [
        .target(
            name: "ArrcadeKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ArrcadeKitTests",
            dependencies: ["ArrcadeKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

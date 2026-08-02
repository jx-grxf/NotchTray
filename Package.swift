// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchTray",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5"),
    ],
    targets: [
        .executableTarget(
            name: "NotchTray",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/NotchTray",
            resources: [
                .process("Resources"),
            ])
    ]
)

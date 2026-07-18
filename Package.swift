// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchTray",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "NotchTray",
            path: "Sources/NotchTray",
            resources: [
                .process("Resources"),
            ])
    ]
)

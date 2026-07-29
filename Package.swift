// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockPeek",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DockPeek",
            path: "Sources/DockPeek"
        )
    ]
)

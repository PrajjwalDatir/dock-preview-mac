// swift-tools-version: 5.9
import PackageDescription

// Sparkle is vendored as a local binary target (see bin/fetch-sparkle.sh) rather than
// a remote package, so builds don't depend on SwiftPM's binary-artifact downloader.
let package = Package(
    name: "DockPeek",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DockPeek",
            dependencies: ["Sparkle"],
            path: "Sources/DockPeek"
        ),
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle.xcframework"
        )
    ]
)

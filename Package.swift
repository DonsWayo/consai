// swift-tools-version: 6.2
import PackageDescription

// Consai is built with SwiftPM (not an .xcodeproj). Xcode 26.5's .xcodeproj SwiftPM
// integration fails to wire up the container SDK's transitive package modules
// (ServiceContextModule, SwiftASN1, ...); SwiftPM builds the same graph cleanly.
// Open this Package.swift directly in Xcode for GUI development, or use `swift build`
// + scripts/bundle.sh to produce Consai.app.
let package = Package(
    name: "Consai",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Apple's container SDK, pinned to the release Orchard ships against (see CLAUDE.md R1).
        .package(url: "https://github.com/apple/container.git", exact: "0.12.3"),
    ],
    targets: [
        // Reusable, UI-free engine.
        .target(
            name: "ConsaiCore",
            dependencies: [
                .product(name: "ContainerAPIClient", package: "container"),
                .product(name: "ContainerResource", package: "container"),
            ],
            path: "ConsaiCore/Sources/ConsaiCore"
        ),
        // The menu bar app (SwiftUI). Bundled into Consai.app by scripts/bundle.sh.
        .executableTarget(
            name: "Consai",
            dependencies: ["ConsaiCore"],
            path: "App",
            exclude: ["Info.plist", "Consai.entitlements"]
        ),
        .testTarget(
            name: "ConsaiCoreTests",
            dependencies: ["ConsaiCore"],
            path: "ConsaiCore/Tests/ConsaiCoreTests"
        ),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ConsaiCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ConsaiCore", targets: ["ConsaiCore"]),
    ],
    dependencies: [
        // Apple's container SDK. Pinned to the release Orchard builds against.
        // All SDK usage is isolated in SDKContainerEngine (see specs/wave-1).
        .package(url: "https://github.com/apple/container.git", exact: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ConsaiCore",
            dependencies: [
                .product(name: "ContainerAPIClient", package: "container"),
            ]
        ),
        .testTarget(
            name: "ConsaiCoreTests",
            dependencies: ["ConsaiCore"]
        ),
    ]
)

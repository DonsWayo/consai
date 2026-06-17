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
        // Apple's container SDK, pinned to 1.0.0 to MATCH the installed `container` daemon —
        // a library/daemon version skew causes XPC wire-decoding errors (e.g. stop options
        // `signal` String-vs-number). The earlier 0.12.3 pin only existed to dodge an Xcode
        // .xcodeproj bug; we build with SwiftPM now, so 1.0.0 is fine (see CLAUDE.md R1/R11).
        .package(url: "https://github.com/apple/container.git", exact: "1.0.0"),
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
        // App orchestration (AppState + mocks + shell launcher) — UI-free, so it is unit-testable.
        .target(
            name: "ConsaiKit",
            dependencies: ["ConsaiCore"],
            path: "ConsaiKit/Sources/ConsaiKit"
        ),
        // The menu bar app (SwiftUI). Bundled into Consai.app by scripts/bundle.sh.
        .executableTarget(
            name: "Consai",
            dependencies: ["ConsaiCore", "ConsaiKit"],
            path: "App",
            exclude: ["Info.plist", "Consai.entitlements", "Resources"]
        ),
        .testTarget(
            name: "ConsaiCoreTests",
            dependencies: ["ConsaiCore"],
            path: "ConsaiCore/Tests/ConsaiCoreTests"
        ),
        .testTarget(
            name: "ConsaiKitTests",
            dependencies: ["ConsaiKit", "ConsaiCore"],
            path: "ConsaiKit/Tests/ConsaiKitTests"
        ),
        // Native-Swift coverage reporter (replaces the old shell script). There is no hosted
        // CI — Apple's container SDK graph can't build on hosted runners — so verification is
        // local. After `swift test --enable-code-coverage`, run `swift run coverage` to print
        // the llvm-cov report for the logic layers. Depends on Foundation only (no ConsaiCore),
        // so `swift run coverage` builds in a second and only shells out to `xcrun` — it never
        // re-invokes SwiftPM, so there is no build-lock deadlock.
        .executableTarget(name: "coverage", path: "Tools/coverage"),
        // Native-Swift app bundler (replaces scripts/bundle.sh): `swift run bundle [debug|release]`
        // builds Consai and assembles an ad-hoc-signed Consai.app.
        .executableTarget(name: "bundle", path: "Tools/bundle"),
        // Native-Swift icon builder (replaces scripts/make-icon.sh): `swift run icon` renders the
        // icon and writes App/Resources/AppIcon.icns.
        .executableTarget(name: "icon", path: "Tools/icon"),
        // Release signing: Developer ID codesign + notarize (notarytool) + staple + DMG.
        // Set CONSAI_IDENTITY / CONSAI_TEAM_ID / CONSAI_APPLE_ID / CONSAI_APP_PWD, then:
        //   swift run bundle && swift run sign
        .executableTarget(name: "sign", path: "Tools/sign"),
    ]
)

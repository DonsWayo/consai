import Foundation

/// App version / build metadata, read from the bundle's Info.plist.
///
/// Pure and injectable: the lookup closure defaults to `Bundle.main` but tests pass a
/// fixed dictionary, so the formatting logic is exercised without a real bundle (the test
/// bundle for `swift test` has no `CFBundleShortVersionString`).
public struct AppInfo: Sendable {
    public let version: String
    public let build: String

    /// `1.2.3 (45)`, or just the version when build is empty/redundant.
    public var displayVersion: String {
        guard !build.isEmpty, build != version else { return version }
        return "\(version) (\(build))"
    }

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Reads `CFBundleShortVersionString` / `CFBundleVersion`, falling back to `"dev"` /
    /// `""` when absent (e.g. running under `swift test`, where there is no app bundle).
    public init(info: (String) -> Any? = { Bundle.main.object(forInfoDictionaryKey: $0) }) {
        self.version = (info("CFBundleShortVersionString") as? String) ?? "dev"
        self.build = (info("CFBundleVersion") as? String) ?? ""
    }

    public static let current = AppInfo()
}

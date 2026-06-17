import Foundation

/// Holds a version check result for one tool.
public struct UpdateAvailability: Sendable, Equatable {
    public let tool: String
    public let current: String
    public let latest: String
    public let releaseURL: URL

    public var hasUpdate: Bool {
        SemVer(latest) > SemVer(current)
    }

    public init(tool: String, current: String, latest: String, releaseURL: URL) {
        self.tool = tool
        self.current = current
        self.latest = latest
        self.releaseURL = releaseURL
    }
}

/// Minimal three-part semver for ordering. Non-numeric tags (e.g. "v1.2.3") are stripped.
struct SemVer: Comparable {
    let major: Int; let minor: Int; let patch: Int

    init(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).drop(while: { !$0.isNumber })
        let parts = String(cleaned).split(separator: ".").prefix(3).map { Int($0) ?? 0 }
        major = parts.count > 0 ? parts[0] : 0
        minor = parts.count > 1 ? parts[1] : 0
        patch = parts.count > 2 ? parts[2] : 0
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

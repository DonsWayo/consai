import Foundation

/// An OCI image present locally.
public struct ContainerImage: Identifiable, Hashable, Sendable {
    public var id: String { reference }
    public let reference: String
    public let digest: String
    /// Compressed on-disk size in bytes (sum of OCI manifest layers); nil if unavailable.
    public let sizeBytes: Int64?

    public init(reference: String, digest: String, sizeBytes: Int64? = nil) {
        self.reference = reference
        self.digest = digest
        self.sizeBytes = sizeBytes
    }

    /// Short digest for display (`sha256:abcd…` → `abcd1234`).
    public var shortDigest: String {
        let hex = digest.contains(":") ? String(digest.split(separator: ":").last ?? "") : digest
        return String(hex.prefix(12))
    }

    /// Formatted size string, e.g. "234 MB". Nil when size is unknown.
    public var formattedSize: String? {
        guard let bytes = sizeBytes, bytes > 0 else { return nil }
        return formatImageBytes(bytes)
    }
}

/// Human-readable compressed image size (uses 1000-based SI units to match Docker/OCI conventions).
public func formatImageBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 { return String(format: "%.2f GB", gb) }
    let mb = Double(bytes) / 1_000_000
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    let kb = Double(bytes) / 1_000
    return String(format: "%.0f KB", kb)
}

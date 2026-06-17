import Foundation

/// An OCI image present locally.
public struct ContainerImage: Identifiable, Hashable, Sendable {
    public var id: String { reference }
    public let reference: String
    public let digest: String

    public init(reference: String, digest: String) {
        self.reference = reference
        self.digest = digest
    }

    /// Short digest for display (`sha256:abcd…` → `abcd1234`).
    public var shortDigest: String {
        let hex = digest.contains(":") ? String(digest.split(separator: ":").last ?? "") : digest
        return String(hex.prefix(12))
    }
}

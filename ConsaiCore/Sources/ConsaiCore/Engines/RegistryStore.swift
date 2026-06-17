import Foundation

/// Persists a `ProjectRegistry` as JSON. Default location:
/// `~/Library/Application Support/Consai/registry.json`. File I/O is isolated here so
/// `ProjectRegistry` itself stays pure and trivially testable.
public struct RegistryStore: Sendable {
    private let fileURL: URL

    /// - Parameter directory: override for tests; defaults to Application Support/Consai.
    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("registry.json")
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Consai", isDirectory: true)
    }

    /// Load the persisted registry, or an empty one if none exists / on decode failure.
    public func load() -> ProjectRegistry {
        guard let data = try? Data(contentsOf: fileURL),
              let registry = try? JSONDecoder().decode(ProjectRegistry.self, from: data)
        else {
            return ProjectRegistry()
        }
        return registry
    }

    /// Persist the registry, creating the directory if needed.
    public func save(_ registry: ProjectRegistry) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(registry)
        try data.write(to: fileURL, options: .atomic)
    }
}

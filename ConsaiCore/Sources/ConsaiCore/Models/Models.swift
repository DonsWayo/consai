import Foundation

/// Lifecycle state of a container, mapped from the SDK's status enum.
public enum ContainerStatus: String, Codable, Sendable {
    case running, stopped, starting, stopping, unknown
}

/// Consai's own container value type. The SDK's `ContainerSnapshot` is mapped into this
/// in `SDKContainerEngine` — SDK types must NOT leak past the engine boundary.
public struct Container: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var image: String
    public var status: ContainerStatus
    /// Primary IPv4 address (Apple gives every container its own), without the CIDR suffix.
    public var ipAddress: String?
    /// Live resident memory in bytes (best-effort; nil until fetched / when stopped).
    public var memoryBytes: UInt64?
    /// Live CPU percentage (total across cores; nil until two samples are available).
    public var cpuPercent: Double?
    public var labels: [String: String]

    public init(
        id: String,
        name: String,
        image: String,
        status: ContainerStatus,
        ipAddress: String? = nil,
        memoryBytes: UInt64? = nil,
        cpuPercent: Double? = nil,
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.ipAddress = ipAddress
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.labels = labels
    }
}

/// CPU percentage from two cumulative `cpuUsageUsec` samples over an elapsed wall-clock
/// window. Total across cores (can exceed 100% on multi-core). Pure for testing.
public func cpuPercent(previousUsec: UInt64, currentUsec: UInt64, elapsedSeconds: Double) -> Double? {
    guard elapsedSeconds > 0, currentUsec >= previousUsec else { return nil }
    let deltaUsec = Double(currentUsec - previousUsec)
    let windowUsec = elapsedSeconds * 1_000_000
    return (deltaUsec / windowUsec) * 100
}

/// Human-readable byte formatting for vitals ("178 MB", "1.0 GB").
public func formatBytes(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    return "\(Int(mb.rounded())) MB"
}

/// Whether a stack was launched by Consai (authoritative, has compose file) or merely
/// inferred from container naming (best-effort, may lack a compose file).
public enum StackOrigin: Sendable, Equatable {
    case launchedByConsai
    case inferred
}

/// A compose project — a group of containers sharing a `<project>-<service>` name prefix.
public struct Stack: Identifiable, Sendable {
    public var id: String { projectName }
    public let projectName: String
    public var composeFilePath: String?
    public var services: [Container]
    public var origin: StackOrigin

    public var runningCount: Int { services.filter { $0.status == .running }.count }
    public var total: Int { services.count }

    public init(
        projectName: String,
        composeFilePath: String? = nil,
        services: [Container],
        origin: StackOrigin
    ) {
        self.projectName = projectName
        self.composeFilePath = composeFilePath
        self.services = services
        self.origin = origin
    }
}

/// Health of the `container` system service.
public enum ServiceStatus: Sendable {
    case running, stopped, unknown
}

/// Typed errors surfaced to the UI as toasts/sheets.
public enum ConsaiError: Error, Sendable {
    case serviceDown
    case composeMissing
    case processFailed(stderr: String)
    case sdk(String)
}

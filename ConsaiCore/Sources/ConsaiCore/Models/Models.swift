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
    public var labels: [String: String]

    public init(
        id: String,
        name: String,
        image: String,
        status: ContainerStatus,
        ipAddress: String? = nil,
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.ipAddress = ipAddress
        self.labels = labels
    }
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

import Foundation

/// Manages individual containers via the apple/container SDK.
/// The concrete `SDKContainerEngine` is implemented in Wave 1.
public protocol ContainerEngine: Sendable {
    func list() async throws -> [Container]
    func start(id: String) async throws
    func stop(id: String) async throws
    func restart(id: String) async throws
    func delete(id: String) async throws
    /// Best-effort live resident memory in bytes; nil if unavailable.
    func memoryUsage(id: String) async -> UInt64?
    /// Best-effort cumulative CPU time in microseconds (for delta-based CPU%); nil if unavailable.
    func cpuUsage(id: String) async -> UInt64?
}

/// Orchestrates compose stacks by shelling out to the `container-compose` CLI.
/// The concrete `CLIComposeEngine` is implemented in Wave 1.
public protocol ComposeEngine: Sendable {
    /// Whether the `container-compose` binary was found. Compose features degrade
    /// gracefully when false — raw container management is unaffected.
    var isAvailable: Bool { get }
    func up(file: URL) async throws
    func down(file: URL) async throws
}

/// Checks/controls the `container` system service.
/// The concrete `CLIServiceHealth` is implemented in Wave 1.
public protocol ServiceHealthChecking: Sendable {
    func status() async -> ServiceStatus
    func start() async throws
    func stop() async throws
}

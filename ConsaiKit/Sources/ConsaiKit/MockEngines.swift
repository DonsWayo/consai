import Foundation
import ConsaiCore

// Simple fixed mocks for previews / the `--render-shots` screenshot harness, so views can be
// rendered with representative data without a live daemon. (Richer, controllable fakes for
// unit tests live in the test target.)

public struct MockContainerEngine: ContainerEngine {
    public let containers: [Container]
    public init(containers: [Container]) { self.containers = containers }
    public func list() async throws -> [Container] { containers }
    public func start(id: String) async throws {}
    public func stop(id: String) async throws {}
    public func restart(id: String) async throws {}
    public func delete(id: String) async throws {}
    public func memoryUsage(id: String) async -> UInt64? { containers.first { $0.id == id }?.memoryBytes }
    public func cpuUsage(id: String) async -> UInt64? { nil }
    public func detail(id: String) async throws -> ContainerDetail {
        ContainerDetail(id: id, image: containers.first { $0.id == id }?.image ?? "img",
                        command: "sleep 3600", env: ["PATH=/usr/bin", "TZ=UTC"],
                        ports: [PortBinding(host: 8080, container: 80, proto: "tcp")],
                        mounts: [MountBinding(source: "/data", destination: "/var/data")],
                        startedAt: nil)
    }
}

public struct MockComposeEngine: ComposeEngine {
    public let isAvailable: Bool
    public init(isAvailable: Bool) { self.isAvailable = isAvailable }
    public func up(file: URL) async throws {}
    public func down(file: URL) async throws {}
}

public struct MockServiceHealth: ServiceHealthChecking {
    public let value: ServiceStatus
    public init(value: ServiceStatus) { self.value = value }
    public func status() async -> ServiceStatus { value }
    public func start() async throws {}
    public func stop() async throws {}
}

public struct MockCreator: ContainerCreating {
    public init() {}
    public func create(_ spec: NewContainerSpec) async throws {}
}

public struct MockImageEngine: ImageEngine {
    public let images: [ContainerImage]
    public init(images: [ContainerImage] = []) { self.images = images }
    public func list() async throws -> [ContainerImage] { images }
    public func pull(reference: String) async throws {}
    public func delete(reference: String) async throws {}
}

public struct MockInfraEngine: InfraEngine {
    public let networks: [ContainerNetwork]
    public let volumes: [ContainerVolume]
    public init(networks: [ContainerNetwork] = [], volumes: [ContainerVolume] = []) {
        self.networks = networks; self.volumes = volumes
    }
    public func listNetworks() async throws -> [ContainerNetwork] { networks }
    public func createNetwork(name: String) async throws {}
    public func deleteNetwork(id: String) async throws {}
    public func listVolumes() async throws -> [ContainerVolume] { volumes }
    public func createVolume(name: String) async throws {}
    public func deleteVolume(name: String) async throws {}
}

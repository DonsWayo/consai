import Foundation
import ConsaiCore

// Lightweight mocks used only by the `--render-shots` screenshot harness, so views can be
// rendered with representative data without a live daemon.

struct MockContainerEngine: ContainerEngine {
    let containers: [Container]
    func list() async throws -> [Container] { containers }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func delete(id: String) async throws {}
    func memoryUsage(id: String) async -> UInt64? { containers.first { $0.id == id }?.memoryBytes }
    func cpuUsage(id: String) async -> UInt64? { nil }  // cpu% needs sampling; mocks preset cpuPercent
    func detail(id: String) async throws -> ContainerDetail {
        ContainerDetail(id: id, image: containers.first { $0.id == id }?.image ?? "img",
                        command: "sleep 3600", env: ["PATH=/usr/bin", "TZ=UTC"],
                        ports: [PortBinding(host: 8080, container: 80, proto: "tcp")],
                        mounts: [MountBinding(source: "/data", destination: "/var/data")],
                        startedAt: nil)
    }
}

struct MockComposeEngine: ComposeEngine {
    let isAvailable: Bool
    func up(file: URL) async throws {}
    func down(file: URL) async throws {}
}

struct MockServiceHealth: ServiceHealthChecking {
    let value: ServiceStatus
    func status() async -> ServiceStatus { value }
    func start() async throws {}
    func stop() async throws {}
}

struct MockCreator: ContainerCreating {
    func create(_ spec: NewContainerSpec) async throws {}
}

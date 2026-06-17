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

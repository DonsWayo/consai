import Foundation
import ContainerAPIClient

/// `InfraEngine`: lists networks/volumes via the SDK; create/delete via the `container
/// network|volume …` CLI (avoids building SDK configuration structs by hand).
public struct SDKInfraEngine: InfraEngine {
    private let binaryURL: URL?
    private let runner: ProcessRunning

    init(binaryURL: URL?, runner: ProcessRunning) {
        self.binaryURL = binaryURL
        self.runner = runner
    }

    public init(binaryPath: String? = nil, runner: ProcessRunning = SystemProcessRunner()) {
        self.init(binaryURL: ContainerBinary.resolve(explicit: binaryPath), runner: runner)
    }

    public func listNetworks() async throws -> [ContainerNetwork] {
        do {
            return try await NetworkClient().list()
                .map { ContainerNetwork(name: $0.name, subnet: String(describing: $0.status.ipv4Subnet)) }
                .sorted { $0.name < $1.name }
        } catch { throw ConsaiError.sdk(String(describing: error)) }
    }

    public func listVolumes() async throws -> [ContainerVolume] {
        do {
            return try await ClientVolume.list()
                .map { ContainerVolume(name: $0.name, driver: $0.driver, source: $0.source) }
                .sorted { $0.name < $1.name }
        } catch { throw ConsaiError.sdk(String(describing: error)) }
    }

    public func createNetwork(name: String) async throws { try await run(["network", "create", name]) }
    public func deleteNetwork(id: String) async throws { try await run(["network", "delete", id]) }
    public func createVolume(name: String) async throws { try await run(["volume", "create", name]) }
    public func deleteVolume(name: String) async throws { try await run(["volume", "delete", name]) }

    private func run(_ arguments: [String]) async throws {
        guard let binaryURL else { throw ConsaiError.sdk("`container` CLI not found") }
        let result = try await runner.run(executable: binaryURL.path, arguments: arguments, cwd: nil)
        if result.exitCode != 0 {
            throw ConsaiError.processFailed(stderr: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    // Pure arg-building for tests.
    static func networkCreateArgs(_ name: String) -> [String] { ["network", "create", name] }
    static func volumeDeleteArgs(_ name: String) -> [String] { ["volume", "delete", name] }
}

import Foundation
import ContainerAPIClient

/// `ImageEngine`: lists images via the apple/container SDK, and pulls/deletes via the
/// `container image …` CLI (pull over the SDK needs a `ContainerSystemConfig` the CLI
/// resolves itself). Pull can be slow, so the runner gets a long timeout.
public struct SDKImageEngine: ImageEngine {
    private let binaryURL: URL?
    private let runner: ProcessRunning

    init(binaryURL: URL?, runner: ProcessRunning) {
        self.binaryURL = binaryURL
        self.runner = runner
    }

    public init(binaryPath: String? = nil, runner: ProcessRunning = SystemProcessRunner(timeout: 600)) {
        self.init(binaryURL: ContainerBinary.resolve(explicit: binaryPath), runner: runner)
    }

    public func list() async throws -> [ContainerImage] {
        do {
            return try await ClientImage.list()
                .map { ContainerImage(reference: $0.reference, digest: $0.digest) }
                .sorted { $0.reference < $1.reference }
        } catch {
            throw ConsaiError.sdk(String(describing: error))
        }
    }

    public func pull(reference: String) async throws {
        try await run(Self.pullArguments(reference: reference))
    }

    public func delete(reference: String) async throws {
        try await run(Self.deleteArguments(reference: reference))
    }

    private func run(_ arguments: [String]) async throws {
        guard let binaryURL else { throw ConsaiError.sdk("`container` CLI not found") }
        let result = try await runner.run(executable: binaryURL.path, arguments: arguments, cwd: nil)
        if result.exitCode != 0 {
            throw ConsaiError.processFailed(stderr: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    // Pure arg-building for tests.
    static func pullArguments(reference: String) -> [String] { ["image", "pull", reference] }
    static func deleteArguments(reference: String) -> [String] { ["image", "delete", reference] }
}

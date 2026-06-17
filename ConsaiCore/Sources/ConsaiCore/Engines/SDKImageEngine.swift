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
            let sdkImages = try await ClientImage.list()
            return try await withThrowingTaskGroup(of: ContainerImage.self) { group in
                for img in sdkImages {
                    group.addTask {
                        let size = try? await Self.compressedSize(img)
                        return ContainerImage(reference: img.reference, digest: img.digest, sizeBytes: size)
                    }
                }
                var result: [ContainerImage] = []
                for try await image in group { result.append(image) }
                return result.sorted { $0.reference < $1.reference }
            }
        } catch {
            throw ConsaiError.sdk(String(describing: error))
        }
    }

    /// Sum of OCI manifest sizes for the arm64 platform variant (compressed, on-disk bytes).
    /// Returns nil gracefully — size is decorative; a failure here must never break the list.
    private static func compressedSize(_ img: ClientImage) async throws -> Int64? {
        let index = try? await img.index()
        guard let manifests = index?.manifests else { return nil }
        var total: Int64 = 0
        for desc in manifests {
            guard let platform = desc.platform,
                  platform.architecture == "arm64" || platform.architecture == "aarch64" else { continue }
            total += desc.size
        }
        return total > 0 ? total : nil
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

import Foundation

/// `ComposeEngine` that shells out to the `container-compose` CLI.
///
/// `container-compose` derives the project from the working directory / the compose file's
/// `name:` field, so we run it with the compose file's directory as `cwd` (it has no `-f`
/// flag). `up` runs detached (`-d`) so Consai doesn't own the stack's lifetime.
public struct CLIComposeEngine: ComposeEngine {
    private let binaryURL: URL?
    private let runner: ProcessRunning

    /// Designated init — inject a known binary + runner (used by tests).
    init(binaryURL: URL?, runner: ProcessRunning) {
        self.binaryURL = binaryURL
        self.runner = runner
    }

    /// Resolves the `container-compose` binary from an explicit path or common locations.
    public init(binaryPath: String? = nil, runner: ProcessRunning = SystemProcessRunner()) {
        self.init(binaryURL: Self.resolveBinary(explicit: binaryPath), runner: runner)
    }

    public var isAvailable: Bool { binaryURL != nil }

    public func up(file: URL) async throws {
        try await runCompose(["up", "-d"], composeFile: file)
    }

    public func down(file: URL) async throws {
        try await runCompose(["down"], composeFile: file)
    }

    private func runCompose(_ arguments: [String], composeFile: URL) async throws {
        guard let binaryURL else { throw ConsaiError.composeMissing }
        let cwd = composeFile.deletingLastPathComponent()
        let result = try await runner.run(executable: binaryURL.path, arguments: arguments, cwd: cwd)
        if result.exitCode != 0 {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ConsaiError.processFailed(stderr: message)
        }
    }

    static func resolveBinary(explicit: String?) -> URL? {
        var candidates: [String] = []
        if let explicit { candidates.append(explicit) }
        candidates += ["/opt/homebrew/bin/container-compose", "/usr/local/bin/container-compose"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

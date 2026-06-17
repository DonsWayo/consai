import Foundation

/// `ServiceHealthChecking` for the `container` system service, via the `container` CLI.
/// (`container system status/start/stop` — these aren't exposed over the SDK's XPC API.)
public struct CLIServiceHealth: ServiceHealthChecking {
    private let binaryURL: URL?
    private let runner: ProcessRunning

    init(binaryURL: URL?, runner: ProcessRunning) {
        self.binaryURL = binaryURL
        self.runner = runner
    }

    public init(binaryPath: String? = nil, runner: ProcessRunning = SystemProcessRunner()) {
        self.init(binaryURL: Self.resolveBinary(explicit: binaryPath), runner: runner)
    }

    public func status() async -> ServiceStatus {
        guard let binaryURL else { return .unknown }
        guard let result = try? await runner.run(
            executable: binaryURL.path, arguments: ["system", "status"], cwd: nil
        ) else {
            return .unknown
        }
        return Self.parseStatus(exitCode: result.exitCode, output: result.stdout + "\n" + result.stderr)
    }

    public func start() async throws {
        try await runSystem(["system", "start"])
    }

    public func stop() async throws {
        try await runSystem(["system", "stop"])
    }

    private func runSystem(_ arguments: [String]) async throws {
        guard let binaryURL else { throw ConsaiError.serviceDown }
        let result = try await runner.run(executable: binaryURL.path, arguments: arguments, cwd: nil)
        if result.exitCode != 0 {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ConsaiError.processFailed(stderr: message)
        }
    }

    /// Interpret `container system status` output. The exact wording is version-dependent,
    /// so we look for negative signals first, then positive, then fall back to exit code.
    static func parseStatus(exitCode: Int32, output: String) -> ServiceStatus {
        let text = output.lowercased()
        if text.contains("not running") || text.contains("stopped") || text.contains("not started") {
            return .stopped
        }
        if text.contains("running") || text.contains("started") {
            return .running
        }
        // A non-zero exit with no recognizable wording means "couldn't determine",
        // not "definitely down" — reserve .stopped for the explicit negative signal above.
        return exitCode == 0 ? .running : .unknown
    }

    public static func resolveBinary(explicit: String?) -> URL? {
        var candidates: [String] = []
        if let explicit { candidates.append(explicit) }
        candidates += ["/usr/local/bin/container", "/opt/homebrew/bin/container"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

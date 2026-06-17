import Foundation

/// Checks whether the `container` CLI, the container service, and `container-compose`
/// are present and operational. Results are best-effort — missing binaries are reported
/// as not-installed rather than errors.
public struct SetupChecker: Sendable {
    private let runner: ProcessRunning

    public init(runner: ProcessRunning = SystemProcessRunner(timeout: 10)) {
        self.runner = runner
    }

    // MARK: - Public checks

    /// Returns (installed, version) for the `container` CLI.
    public func checkContainer(binaryPath: String? = nil) async -> (installed: Bool, version: String?) {
        let path = resolvedBinary(explicit: binaryPath, candidates: [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
        ])
        guard let path else { return (false, nil) }
        let result = try? await runner.run(executable: path, arguments: ["--version"], cwd: nil)
        guard let result, result.exitCode == 0 else { return (true, nil) }
        return (true, extractVersion(from: result.stdout.isEmpty ? result.stderr : result.stdout))
    }

    /// Returns true when `container system status` reports the daemon is running.
    public func checkService(binaryPath: String? = nil) async -> Bool {
        let path = resolvedBinary(explicit: binaryPath, candidates: [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
        ])
        guard let path else { return false }
        guard let result = try? await runner.run(executable: path, arguments: ["system", "status"], cwd: nil)
        else { return false }
        let out = (result.stdout + result.stderr).lowercased()
        return result.exitCode == 0 || out.contains("running")
    }

    /// Returns (installed, version) for `container-compose`.
    public func checkCompose(binaryPath: String? = nil) async -> (installed: Bool, version: String?) {
        let path = resolvedBinary(explicit: binaryPath, candidates: [
            "/usr/local/bin/container-compose",
            "/opt/homebrew/bin/container-compose",
        ])
        guard let path else { return (false, nil) }
        let result = try? await runner.run(executable: path, arguments: ["--version"], cwd: nil)
        guard let result, result.exitCode == 0 else { return (true, nil) }
        return (true, extractVersion(from: result.stdout.isEmpty ? result.stderr : result.stdout))
    }

    // MARK: - Helpers

    private func resolvedBinary(explicit: String?, candidates: [String]) -> String? {
        if let explicit, FileManager.default.isExecutableFile(atPath: explicit) { return explicit }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func extractVersion(from text: String) -> String? {
        let pattern = try? NSRegularExpression(pattern: #"\d+\.\d+(?:\.\d+)?"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern?.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}

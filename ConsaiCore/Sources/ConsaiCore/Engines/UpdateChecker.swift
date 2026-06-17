import Foundation

/// Checks for new releases of `container` and `container-compose` against GitHub.
/// Results are best-effort: network failures and rate limits are silently swallowed.
public struct UpdateChecker: Sendable {
    private let runner: ProcessRunning
    private let session: URLSession

    public init(
        runner: ProcessRunning = SystemProcessRunner(timeout: 10),
        session: URLSession = .shared
    ) {
        self.runner = runner
        self.session = session
    }

    // MARK: - Public API

    /// Check the installed `container` CLI against the latest GitHub release.
    public func checkContainer(binaryPath: String? = nil) async -> UpdateAvailability? {
        let binary = ContainerBinary.resolve(explicit: binaryPath)?.path ?? "/usr/local/bin/container"
        guard let current = await installedVersion(binary: binary, tool: "container") else { return nil }
        guard let (latest, url) = await githubLatest(repo: "apple/container") else { return nil }
        return UpdateAvailability(tool: "container", current: current, latest: latest, releaseURL: url)
    }

    /// Check the installed `container-compose` CLI against the latest GitHub release.
    /// Returns nil if compose is not installed.
    public func checkCompose(binaryPath: String? = nil) async -> UpdateAvailability? {
        let binary = CLIComposeEngine.resolveBinary(explicit: binaryPath)?.path ?? "/usr/local/bin/container-compose"
        guard let current = await installedVersion(binary: binary, tool: "container-compose") else { return nil }
        guard let (latest, url) = await githubLatest(repo: "Mcrich23/Container-Compose") else { return nil }
        return UpdateAvailability(tool: "container-compose", current: current, latest: latest, releaseURL: url)
    }

    // MARK: - Internals

    /// Run `<binary> --version` and extract the semver string.
    /// Output formats handled:
    ///   "container CLI version 1.0.0 (build: release, commit: abc)"
    ///   "container-compose version 1.0.0"
    private func installedVersion(binary: String, tool: String) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: binary) else { return nil }
        guard let result = try? await runner.run(executable: binary, arguments: ["--version"], cwd: nil),
              result.exitCode == 0 else { return nil }
        let text = result.stdout.isEmpty ? result.stderr : result.stdout
        return extractVersion(from: text)
    }

    /// Fetch the latest release tag from the GitHub API (unauthenticated, 60 req/h).
    /// Returns (tag_name stripped of leading 'v', html_url).
    private func githubLatest(repo: String) async -> (String, URL)? {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: apiURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Consai/1.0 (github.com/DonsWayo/consai)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let htmlURL = (json["html_url"] as? String).flatMap({ URL(string: $0) })
        else { return nil }
        return (String(tag.drop(while: { $0 == "v" })), htmlURL)
    }

    /// Extract the first semver-looking token (digits and dots) from a version string.
    private func extractVersion(from text: String) -> String? {
        let pattern = try? NSRegularExpression(pattern: #"\d+\.\d+(?:\.\d+)?"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern?.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}

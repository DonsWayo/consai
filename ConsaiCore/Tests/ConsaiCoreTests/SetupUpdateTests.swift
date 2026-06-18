import Testing
import Foundation
@testable import ConsaiCore

// MARK: - SemVer + UpdateAvailability

@Suite struct SemVerTests {
    @Test func stripsLeadingV() {
        #expect(SemVer("v1.2.3") == SemVer("1.2.3"))
    }

    @Test func ordersCorrectly() {
        #expect(SemVer("1.0.0") < SemVer("1.1.0"))
        #expect(SemVer("1.1.0") < SemVer("2.0.0"))
        #expect(SemVer("1.0.9") < SemVer("1.0.10"))
        #expect(!(SemVer("2.0.0") < SemVer("1.9.9")))
    }

    @Test func equalVersionsAreNotLessThan() {
        #expect(!(SemVer("1.2.3") < SemVer("1.2.3")))
    }

    @Test func handlesShortVersions() {
        #expect(SemVer("1.0") < SemVer("1.1"))
        #expect(SemVer("2") < SemVer("3"))
    }

    @Test func hasUpdateTrueWhenLatestIsNewer() {
        let ua = UpdateAvailability(
            tool: "container", current: "1.0.0", latest: "1.1.0",
            releaseURL: URL(string: "https://example.com")!)
        #expect(ua.hasUpdate)
    }

    @Test func hasUpdateFalseWhenUpToDate() {
        let ua = UpdateAvailability(
            tool: "container", current: "1.1.0", latest: "1.1.0",
            releaseURL: URL(string: "https://example.com")!)
        #expect(!ua.hasUpdate)
    }

    @Test func hasUpdateFalseWhenInstalledIsNewer() {
        let ua = UpdateAvailability(
            tool: "container", current: "2.0.0", latest: "1.9.9",
            releaseURL: URL(string: "https://example.com")!)
        #expect(!ua.hasUpdate)
    }
}

// MARK: - SetupChecker
//
// These tests inject a real executable temp file so SetupChecker.resolvedBinary
// picks it up via the explicit binaryPath argument (highest priority).

@Suite struct SetupCheckerTests {
    @Test func containerInstalledWithVersionOnSuccess() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 0, stdout: "container CLI version 1.0.0", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = SetupChecker(runner: spy)
        let result = await checker.checkContainer(binaryPath: exe.path)
        #expect(result.installed)
        #expect(result.version == "1.0.0")
        #expect(spy.invocations.first?.arguments == ["--version"])
    }

    @Test func containerInstalledWithNilVersionWhenCommandExitsNonZero() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = SetupChecker(runner: spy)
        let result = await checker.checkContainer(binaryPath: exe.path)
        // Binary present → installed; exit non-zero → version unavailable, not "missing"
        #expect(result.installed)
        #expect(result.version == nil)
    }

    @Test func versionFallsBackToStderrWhenStdoutEmpty() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 0, stdout: "", stderr: "version 2.3.1"))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = SetupChecker(runner: spy)
        let result = await checker.checkContainer(binaryPath: exe.path)
        #expect(result.version == "2.3.1")
    }

    @Test func serviceRunningWhenOutputContainsRunning() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 0, stdout: "apiserver is running", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = SetupChecker(runner: spy)
        #expect(await checker.checkService(binaryPath: exe.path))
        #expect(spy.invocations.first?.arguments == ["system", "status"])
    }

    @Test func serviceNotRunningWhenOutputContainsNotRunning() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 1, stdout: "service is not running", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = SetupChecker(runner: spy)
        #expect(!(await checker.checkService(binaryPath: exe.path)))
    }

    @Test func serviceRunningWhenExitZeroAndNoStatusKeyword() async throws {
        // No "running"/"not running" keyword — exit code 0 → treat as running.
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 0, stdout: "OK", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = SetupChecker(runner: spy)
        #expect(await checker.checkService(binaryPath: exe.path))
    }

    @Test func composeInstalledWithVersion() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 0, stdout: "container-compose version 0.5.2", stderr: ""))
        let exe = try makeExecutable(name: "container-compose")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = SetupChecker(runner: spy)
        let result = await checker.checkCompose(binaryPath: exe.path)
        #expect(result.installed)
        #expect(result.version == "0.5.2")
        #expect(spy.invocations.first?.arguments == ["--version"])
    }
}

// MARK: - UpdateChecker
//
// Network is stubbed with OfflineURLProtocol so tests are deterministic and offline.
// The tests focus on the subprocess invocation layer (installedVersion).

/// URLProtocol that immediately rejects every request — keeps tests offline and fast.
private final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

private func offlineSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OfflineURLProtocol.self]
    return URLSession(configuration: config)
}

@Suite struct UpdateCheckerTests {
    @Test func sendsVersionFlagToContainerBinary() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(
            exitCode: 0, stdout: "container CLI version 1.0.0 (build: release, commit: abc)", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = UpdateChecker(runner: spy, session: offlineSession())
        _ = await checker.checkContainer(binaryPath: exe.path)
        #expect(spy.invocations.first?.arguments == ["--version"])
    }

    @Test func containerReturnsNilWhenVersionExitsNonZero() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = UpdateChecker(runner: spy, session: offlineSession())
        let result = await checker.checkContainer(binaryPath: exe.path)
        #expect(result == nil)
    }

    @Test func containerReturnsNilWhenNetworkUnavailable() async throws {
        // Binary found + version parsed, but github API unreachable → nil result.
        let spy = SpyProcessRunner(result: ProcessResult(
            exitCode: 0, stdout: "container CLI version 1.0.0", stderr: ""))
        let exe = try makeExecutable(name: "container")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = UpdateChecker(runner: spy, session: offlineSession())
        let result = await checker.checkContainer(binaryPath: exe.path)
        #expect(result == nil)
    }

    @Test func composeReturnsNilWhenVersionExitsNonZero() async throws {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: ""))
        let exe = try makeExecutable(name: "container-compose")
        defer { try? FileManager.default.removeItem(at: exe) }
        let checker = UpdateChecker(runner: spy, session: offlineSession())
        let result = await checker.checkCompose(binaryPath: exe.path)
        #expect(result == nil)
    }
}

// MARK: - Shared helper

private func makeExecutable(name: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(name)-\(UUID().uuidString)")
    try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

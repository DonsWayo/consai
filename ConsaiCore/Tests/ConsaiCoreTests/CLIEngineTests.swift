import Testing
import Foundation
@testable import ConsaiCore

/// Records the last invocation and returns a canned result, so we can assert argv/cwd
/// without spawning a process.
final class SpyProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Sendable { let executable: String; let arguments: [String]; let cwd: URL? }
    private(set) var invocations: [Invocation] = []
    var result: ProcessResult

    init(result: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: "")) {
        self.result = result
    }

    func run(executable: String, arguments: [String], cwd: URL?) async throws -> ProcessResult {
        invocations.append(Invocation(executable: executable, arguments: arguments, cwd: cwd))
        return result
    }
}

@Suite struct CLIComposeEngineTests {
    private let binary = URL(fileURLWithPath: "/usr/local/bin/container-compose")
    private let composeFile = URL(fileURLWithPath: "/Users/me/projects/shop/docker-compose.yml")

    @Test func upRunsDetachedInComposeFileDirectory() async throws {
        let spy = SpyProcessRunner()
        let engine = CLIComposeEngine(binaryURL: binary, runner: spy)
        try await engine.up(file: composeFile)

        let invocation = try #require(spy.invocations.first)
        #expect(invocation.executable == "/usr/local/bin/container-compose")
        #expect(invocation.arguments == ["up", "-d"])
        #expect(invocation.cwd?.path == "/Users/me/projects/shop")
    }

    @Test func downRunsInComposeFileDirectory() async throws {
        let spy = SpyProcessRunner()
        let engine = CLIComposeEngine(binaryURL: binary, runner: spy)
        try await engine.down(file: composeFile)

        let invocation = try #require(spy.invocations.first)
        #expect(invocation.arguments == ["down"])
        #expect(invocation.cwd?.path == "/Users/me/projects/shop")
    }

    @Test func nonZeroExitThrowsProcessFailedWithStderr() async {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: "boom"))
        let engine = CLIComposeEngine(binaryURL: binary, runner: spy)
        await #expect(throws: ConsaiError.self) {
            try await engine.up(file: composeFile)
        }
    }

    @Test func unavailableWhenBinaryMissing() async {
        let engine = CLIComposeEngine(binaryURL: nil, runner: SpyProcessRunner())
        #expect(engine.isAvailable == false)
        await #expect(throws: ConsaiError.self) {
            try await engine.up(file: composeFile)
        }
    }
}

@Suite struct CLIContainerCreatorTests {
    @Test func buildsRunArgumentsInOrder() {
        let spec = NewContainerSpec(
            image: "nginx:latest",
            name: "web",
            env: ["B": "2", "A": "1"],
            ports: [PortMapping(hostPort: 8080, containerPort: 80)],
            volumes: [VolumeMount(hostPath: "/data", containerPath: "/var/data")],
            command: "nginx -g daemon off;"
        )
        let args = CLIContainerCreator.runArguments(for: spec)
        #expect(args == [
            "run", "-d",
            "--name", "web",
            "--env", "A=1", "--env", "B=2",          // env sorted by key
            "--publish", "8080:80",
            "--volume", "/data:/var/data",
            "nginx:latest",
            "nginx", "-g", "daemon", "off;",
        ])
    }

    @Test func minimalSpecIsJustRunImage() {
        let args = CLIContainerCreator.runArguments(for: NewContainerSpec(image: "redis"))
        #expect(args == ["run", "-d", "redis"])
    }

    @Test func tokenizerHonorsQuotesAndEscapes() {
        #expect(CLIContainerCreator.tokenize(#"sh -c "echo hello world""#) == ["sh", "-c", "echo hello world"])
        #expect(CLIContainerCreator.tokenize("echo 'a b'  c") == ["echo", "a b", "c"])
        #expect(CLIContainerCreator.tokenize(#"a\ b c"#) == ["a b", "c"])
        #expect(CLIContainerCreator.tokenize("plain command here") == ["plain", "command", "here"])
        // Dangling backslash → literal, no spurious empty trailing token.
        #expect(CLIContainerCreator.tokenize(#"a b\"#) == ["a", "b\\"])
        #expect(CLIContainerCreator.tokenize("") == [])
    }
}

@Suite struct CLIServiceHealthTests {
    @Test func parsesNegativeSignalsAsStopped() {
        #expect(CLIServiceHealth.parseStatus(exitCode: 0, output: "apiserver is not running") == .stopped)
        #expect(CLIServiceHealth.parseStatus(exitCode: 0, output: "service stopped") == .stopped)
    }

    @Test func parsesRunningAsRunning() {
        #expect(CLIServiceHealth.parseStatus(exitCode: 0, output: "apiserver is running") == .running)
    }

    @Test func fallsBackToExitCode() {
        #expect(CLIServiceHealth.parseStatus(exitCode: 0, output: "???") == .running)
        // Non-zero exit with no recognizable wording = "couldn't determine", not "down".
        #expect(CLIServiceHealth.parseStatus(exitCode: 1, output: "???") == .unknown)
    }

    @Test func startSendsSystemStart() async throws {
        let spy = SpyProcessRunner()
        let health = CLIServiceHealth(binaryURL: URL(fileURLWithPath: "/usr/local/bin/container"), runner: spy)
        try await health.start()
        #expect(spy.invocations.first?.arguments == ["system", "start"])
    }
}

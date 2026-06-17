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
        #expect(invocation.arguments == ["up", "-d", "--file", composeFile.path])
        #expect(invocation.cwd?.path == "/Users/me/projects/shop")
    }

    @Test func downRunsInComposeFileDirectory() async throws {
        let spy = SpyProcessRunner()
        let engine = CLIComposeEngine(binaryURL: binary, runner: spy)
        try await engine.down(file: composeFile)

        let invocation = try #require(spy.invocations.first)
        #expect(invocation.arguments == ["down", "--file", composeFile.path])
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

    @Test func availableWhenBinaryPresent() {
        #expect(CLIComposeEngine(binaryURL: binary, runner: SpyProcessRunner()).isAvailable)
    }

    @Test func downFailureFallsBackToStdoutWhenStderrEmpty() async {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 1, stdout: "no such stack", stderr: ""))
        let engine = CLIComposeEngine(binaryURL: binary, runner: spy)
        await #expect(throws: ConsaiError.self) { try await engine.down(file: composeFile) }
    }

    @Test func resolveBinaryPrefersExecutableExplicitPath() throws {
        let exe = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("container-compose-\(UUID().uuidString)")
        try "#!/bin/sh\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        defer { try? FileManager.default.removeItem(at: exe) }
        #expect(CLIComposeEngine.resolveBinary(explicit: exe.path) == exe)
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

@Suite struct SDKImageEngineTests {
    @Test func buildsImageCommandArgs() {
        #expect(SDKImageEngine.pullArguments(reference: "docker.io/library/nginx:latest")
                == ["image", "pull", "docker.io/library/nginx:latest"])
        #expect(SDKImageEngine.deleteArguments(reference: "alpine:latest")
                == ["image", "delete", "alpine:latest"])
    }

    @Test func shortDigestTrimsAlgoAndLength() {
        let img = ContainerImage(reference: "nginx:latest", digest: "sha256:abcdef0123456789aaaa")
        #expect(img.shortDigest == "abcdef012345")
    }
}

@Suite struct SDKInfraEngineTests {
    @Test func buildsInfraCommandArgs() {
        #expect(SDKInfraEngine.networkCreateArgs("backend") == ["network", "create", "backend"])
        #expect(SDKInfraEngine.volumeDeleteArgs("pgdata") == ["volume", "delete", "pgdata"])
    }
}

@Suite struct ContainerDetailTests {
    @Test func execCommandBuildsInteractiveShell() {
        #expect(containerExecCommand(binary: "/usr/local/bin/container", id: "web")
                == "/usr/local/bin/container exec -it web sh")
        #expect(containerExecCommand(binary: "container", id: "db", shell: "bash")
                == "container exec -it db bash")
    }

    @Test func validatesContainerNamesAndRejectsInjection() {
        #expect(isValidContainerName("shop-api"))
        #expect(isValidContainerName("my_db.1"))
        #expect(!isValidContainerName(""))
        #expect(!isValidContainerName("-leadingdash"))   // must start alphanumeric
        // Injection attempts must be rejected before reaching the shell/AppleScript.
        #expect(!isValidContainerName("web; rm -rf /"))
        #expect(!isValidContainerName("a$(whoami)"))
        #expect(!isValidContainerName("a\"; do shell script \"x"))
        #expect(!isValidContainerName("a b"))
        #expect(!isValidContainerName("a\nb"))
    }
}

@Suite struct FormatBytesTests {
    @Test func formatsMBAndGB() {
        #expect(formatBytes(38 * 1_048_576) == "38 MB")
        #expect(formatBytes(1024 * 1_048_576) == "1.0 GB")
        #expect(formatBytes(0) == "0 MB")
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

    @Test func stopSendsSystemStop() async throws {
        let spy = SpyProcessRunner()
        let health = CLIServiceHealth(binaryURL: URL(fileURLWithPath: "/usr/local/bin/container"), runner: spy)
        try await health.stop()
        #expect(spy.invocations.first?.arguments == ["system", "stop"])
    }

    @Test func statusRunsCliAndParsesOutput() async {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 0, stdout: "apiserver is running", stderr: ""))
        let health = CLIServiceHealth(binaryURL: URL(fileURLWithPath: "/usr/local/bin/container"), runner: spy)
        let status = await health.status()
        #expect(status == .running)
        #expect(spy.invocations.first?.arguments == ["system", "status"])
    }

    @Test func statusUnknownWhenBinaryMissing() async {
        let health = CLIServiceHealth(binaryURL: nil, runner: SpyProcessRunner())
        #expect(await health.status() == .unknown)
    }

    @Test func startThrowsOnNonZeroExitAndMissingBinary() async {
        let failing = SpyProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: "permission denied"))
        let health = CLIServiceHealth(binaryURL: URL(fileURLWithPath: "/usr/local/bin/container"), runner: failing)
        await #expect(throws: ConsaiError.self) { try await health.start() }

        let noBinary = CLIServiceHealth(binaryURL: nil, runner: SpyProcessRunner())
        await #expect(throws: ConsaiError.self) { try await noBinary.start() }
    }

    @Test func resolveBinaryPrefersExecutableExplicitPath() throws {
        // An explicit, executable path is preferred over the built-in default candidates.
        let exe = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("container-\(UUID().uuidString)")
        try "#!/bin/sh\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        defer { try? FileManager.default.removeItem(at: exe) }
        #expect(CLIServiceHealth.resolveBinary(explicit: exe.path) == exe)
    }
}

@Suite struct CLIContainerCreatorRunTests {
    @Test func createSpawnsRunWithBuiltArguments() async throws {
        let spy = SpyProcessRunner()
        let creator = CLIContainerCreator(binaryURL: URL(fileURLWithPath: "/usr/local/bin/container"), runner: spy)
        try await creator.create(NewContainerSpec(image: "redis", name: "cache"))
        #expect(spy.invocations.first?.executable == "/usr/local/bin/container")
        #expect(spy.invocations.first?.arguments == ["run", "-d", "--name", "cache", "redis"])
    }

    @Test func createThrowsOnNonZeroExit() async {
        let spy = SpyProcessRunner(result: ProcessResult(exitCode: 125, stdout: "", stderr: "no such image"))
        let creator = CLIContainerCreator(binaryURL: URL(fileURLWithPath: "/usr/local/bin/container"), runner: spy)
        await #expect(throws: ConsaiError.self) { try await creator.create(NewContainerSpec(image: "ghost")) }
    }

    @Test func createThrowsWhenBinaryMissing() async {
        let creator = CLIContainerCreator(binaryURL: nil, runner: SpyProcessRunner())
        await #expect(throws: ConsaiError.self) { try await creator.create(NewContainerSpec(image: "redis")) }
    }
}

@Suite struct RegistryStorePersistenceTests {
    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("consai-store-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RegistryStore(directory: dir)

        var registry = ProjectRegistry()
        registry.record(project: "shop", composeFile: URL(fileURLWithPath: "/p/shop/docker-compose.yml"))
        try store.save(registry)

        let loaded = store.load()
        #expect(loaded.knownProjects["shop"]?.path == "/p/shop/docker-compose.yml")
        #expect(loaded.recentComposeFiles.count == 1)
        #expect(loaded == registry)
    }

    @Test func loadFromEmptyDirectoryReturnsEmptyRegistry() {
        let store = RegistryStore(directory: tempDir())
        #expect(store.load() == ProjectRegistry())
    }

    @Test func loadIgnoresCorruptFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(to: dir.appendingPathComponent("registry.json"), atomically: true, encoding: .utf8)
        // Corrupt JSON decodes to an empty registry rather than throwing.
        #expect(RegistryStore(directory: dir).load() == ProjectRegistry())
    }

    @Test func defaultDirectoryIsUnderApplicationSupport() {
        #expect(RegistryStore.defaultDirectory().path.hasSuffix("/Consai"))
    }
}

@Suite struct ContainerImageDigestTests {
    @Test func shortDigestHandlesDigestWithoutAlgorithmPrefix() {
        // No ":" → take the raw hex prefix, not an empty split tail.
        #expect(ContainerImage(reference: "x", digest: "abcdef0123456789").shortDigest == "abcdef012345")
        #expect(ContainerImage(reference: "x", digest: "short").shortDigest == "short")
        #expect(ContainerImage(reference: "nginx:latest", digest: "d").id == "nginx:latest")
    }
}

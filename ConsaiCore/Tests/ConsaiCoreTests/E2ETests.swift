import Testing
import Foundation
@testable import ConsaiCore

/// End-to-end tests that exercise the REAL `container` daemon (create/start/stop/delete,
/// service status, compose up/down). They are destructive (create + delete throwaway
/// `consai-e2e-*` resources), so they only run when `CONSAI_E2E=1` is set. They never touch
/// containers they didn't create.
///
///   CONSAI_E2E=1 swift test
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CONSAI_E2E"] == "1"))
struct E2ETests {
    static let image = "docker.io/library/alpine:latest"

    @Test func serviceIsRunning() async {
        let status = await CLIServiceHealth().status()
        #expect(status == .running, "container system service should be running for E2E")
    }

    @Test func listDoesNotThrow() async throws {
        let containers = try await SDKContainerEngine().list()
        // No assertion on contents (the machine may have unrelated containers); just that
        // the real XPC list call round-trips and maps to our model.
        #expect(containers.allSatisfy { !$0.id.isEmpty })
    }

    @Test func fullContainerLifecycle() async throws {
        let name = "consai-e2e-\(UUID().uuidString.prefix(8).lowercased())"
        let creator = CLIContainerCreator(runner: SystemProcessRunner(timeout: 180))
        let engine = SDKContainerEngine()

        do {
            // create + run
            try await creator.create(NewContainerSpec(image: Self.image, name: name, command: "sleep 300"))
            var list = try await engine.list()
            #expect(list.contains { $0.name == name }, "created container should appear in list")

            // stop
            try await engine.stop(id: name)

            // start again (verifies the bootstrap+start path)
            try await engine.start(id: name)

            // delete
            try await engine.delete(id: name)
            list = try await engine.list()
            #expect(!list.contains { $0.name == name }, "deleted container should be gone")
        } catch {
            try? await engine.delete(id: name)   // best-effort cleanup on failure
            throw error
        }
    }

    @Test(.enabled(if: CLIComposeEngine().isAvailable))
    func composeUpDownLifecycle() async throws {
        let project = "consaie2e\(UUID().uuidString.prefix(6).lowercased())"
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let composeFile = dir.appendingPathComponent("docker-compose.yml")
        let yaml = """
        name: \(project)
        services:
          one:
            image: \(Self.image)
            command: ["sleep", "300"]
          two:
            image: \(Self.image)
            command: ["sleep", "300"]
        """
        try yaml.write(to: composeFile, atomically: true, encoding: .utf8)

        let compose = CLIComposeEngine(runner: SystemProcessRunner(timeout: 240))
        let engine = SDKContainerEngine()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            try await compose.up(file: composeFile)

            let list = try await engine.list()
            let registry = ProjectRegistry(knownProjects: [project: composeFile])
            let (stacks, _) = registry.assemble(containers: list)
            let stack = stacks.first { $0.projectName == project }
            #expect(stack != nil, "compose project should be grouped into a stack")
            #expect((stack?.services.count ?? 0) >= 2, "stack should contain both services")
            #expect(stack?.origin == .launchedByConsai)

            try await compose.down(file: composeFile)
        } catch {
            try? await compose.down(file: composeFile)   // best-effort teardown
            throw error
        }
    }
}

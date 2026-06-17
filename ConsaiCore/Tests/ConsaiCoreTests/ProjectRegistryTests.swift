import Testing
import Foundation
@testable import ConsaiCore

@Suite struct ProjectRegistryTests {

    private func c(_ id: String, _ name: String, _ status: ContainerStatus = .running) -> Container {
        Container(id: id, name: name, image: "img", status: status)
    }

    @Test func groupsKnownProjectByPrefixAndLeavesLonersStandalone() {
        var registry = ProjectRegistry()
        registry.record(project: "myapp", composeFile: URL(fileURLWithPath: "/tmp/myapp/docker-compose.yml"))

        let result = registry.assemble(containers: [
            c("1", "myapp-web"), c("2", "myapp-db"), c("3", "lonely", .stopped),
        ])

        #expect(result.stacks.count == 1)
        let stack = try! #require(result.stacks.first)
        #expect(stack.projectName == "myapp")
        #expect(stack.services.count == 2)
        #expect(stack.runningCount == 2)
        #expect(stack.origin == .launchedByConsai)
        #expect(stack.composeFilePath?.hasSuffix("docker-compose.yml") == true)

        #expect(result.standalone.map(\.name) == ["lonely"])
    }

    @Test func unknownSingleContainerIsStandalone() {
        let result = ProjectRegistry().assemble(containers: [c("1", "redis")])
        #expect(result.stacks.isEmpty)
        #expect(result.standalone.count == 1)
    }

    @Test func infersStackFromSharedPrefixWhenOptedIn() {
        let result = ProjectRegistry().assemble(containers: [
            c("1", "shop-web"), c("2", "shop-db"), c("3", "shop-cache"),
        ], inferStacks: true)
        #expect(result.stacks.count == 1)
        let stack = try! #require(result.stacks.first)
        #expect(stack.projectName == "shop")
        #expect(stack.origin == .inferred)
        #expect(stack.composeFilePath == nil)
        #expect(stack.services.count == 3)
        #expect(result.standalone.isEmpty)
    }

    @Test func doesNotInferStacksByDefault() {
        // Default (inference off): unrelated containers sharing a prefix stay standalone (#12).
        let result = ProjectRegistry().assemble(containers: [
            c("1", "qa-web"), c("2", "qa-cache"),
        ])
        #expect(result.stacks.isEmpty)
        #expect(result.standalone.map(\.name).sorted() == ["qa-cache", "qa-web"])
    }

    @Test func groupsByComposeProjectLabelEvenWithInferenceOff() {
        let lbl = ProjectRegistry.composeProjectLabel
        let labeledApi = Container(id: "1", name: "shop-api", image: "img", status: .running, labels: [lbl: "shop"])
        let labeledWorker = Container(id: "2", name: "shop-worker", image: "img", status: .running, labels: [lbl: "shop"])
        let result = ProjectRegistry().assemble(containers: [labeledApi, labeledWorker, c("3", "qa-web")])

        #expect(result.stacks.count == 1)
        let stack = try! #require(result.stacks.first)
        #expect(stack.projectName == "shop")
        #expect(stack.origin == .composeLabeled)
        #expect(stack.services.count == 2)
        #expect(result.standalone.map(\.name) == ["qa-web"])   // unlabeled stays standalone
    }

    @Test func singleHyphenatedContainerIsNotAStack() {
        let result = ProjectRegistry().assemble(containers: [c("1", "alone-web")])
        #expect(result.stacks.isEmpty)
        #expect(result.standalone.map(\.name) == ["alone-web"])
    }

    @Test func knownProjectWithNoLiveContainersIsEmptyStack() {
        var registry = ProjectRegistry()
        registry.record(project: "myapp", composeFile: URL(fileURLWithPath: "/tmp/myapp/compose.yml"))
        let result = registry.assemble(containers: [c("1", "redis")])

        #expect(result.stacks.count == 1)
        #expect(result.stacks.first?.projectName == "myapp")
        #expect(result.stacks.first?.services.isEmpty == true)
        #expect(result.standalone.map(\.name) == ["redis"])
    }

    @Test func longerKnownProjectWinsOverShorterPrefix() {
        var registry = ProjectRegistry()
        registry.record(project: "app", composeFile: URL(fileURLWithPath: "/a/compose.yml"))
        registry.record(project: "app-staging", composeFile: URL(fileURLWithPath: "/b/compose.yml"))

        let result = registry.assemble(containers: [
            c("1", "app-staging-web"), c("2", "app-web"),
        ])
        let staging = try! #require(result.stacks.first { $0.projectName == "app-staging" })
        #expect(staging.services.map(\.id) == ["1"])
        let app = try! #require(result.stacks.first { $0.projectName == "app" })
        #expect(app.services.map(\.id) == ["2"])
    }

    @Test func recentComposeFilesAreDedupedMostRecentFirst() {
        var registry = ProjectRegistry()
        let a = URL(fileURLWithPath: "/a/compose.yml")
        let b = URL(fileURLWithPath: "/b/compose.yml")
        registry.noteRecent(a)
        registry.noteRecent(b)
        registry.noteRecent(a)
        #expect(registry.recentComposeFiles == [a, b])
    }
}

@Suite struct RegistryStoreTests {
    @Test func roundTripsThroughDisk() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("consai-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = RegistryStore(directory: tmp)
        #expect(store.load() == ProjectRegistry())   // empty when nothing saved

        var registry = ProjectRegistry()
        registry.record(project: "myapp", composeFile: URL(fileURLWithPath: "/tmp/myapp/compose.yml"))
        try store.save(registry)

        let reloaded = store.load()
        #expect(reloaded == registry)
        #expect(reloaded.knownProjects["myapp"]?.path == "/tmp/myapp/compose.yml")
    }
}

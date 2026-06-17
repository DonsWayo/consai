import Testing
import Foundation
@testable import ConsaiCore

@Suite struct ProjectRegistryTests {

    @Test func groupsKnownProjectByPrefixAndLeavesLonersStandalone() {
        var registry = ProjectRegistry()
        registry.record(
            project: "myapp",
            composeFile: URL(fileURLWithPath: "/tmp/myapp/docker-compose.yml")
        )

        let containers = [
            Container(id: "1", name: "myapp-web", image: "nginx", status: .running),
            Container(id: "2", name: "myapp-db", image: "postgres", status: .running),
            Container(id: "3", name: "lonely", image: "redis", status: .stopped),
        ]

        let result = registry.assemble(containers: containers)

        #expect(result.stacks.count == 1)
        let stack = try! #require(result.stacks.first)
        #expect(stack.projectName == "myapp")
        #expect(stack.services.count == 2)
        #expect(stack.runningCount == 2)
        #expect(stack.origin == .launchedByConsai)

        #expect(result.standalone.count == 1)
        #expect(result.standalone.first?.name == "lonely")
    }

    @Test func unknownContainersAreStandalone() {
        let registry = ProjectRegistry()
        let containers = [
            Container(id: "1", name: "redis", image: "redis", status: .running),
        ]
        let result = registry.assemble(containers: containers)
        #expect(result.stacks.isEmpty)
        #expect(result.standalone.count == 1)
    }
}

extension StackOrigin: @retroactive Equatable {
    public static func == (lhs: StackOrigin, rhs: StackOrigin) -> Bool {
        switch (lhs, rhs) {
        case (.launchedByConsai, .launchedByConsai), (.inferred, .inferred): return true
        default: return false
        }
    }
}

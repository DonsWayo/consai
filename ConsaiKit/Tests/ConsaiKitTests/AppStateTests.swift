import Testing
import Foundation
@testable import ConsaiKit
@testable import ConsaiCore

// MARK: - Controllable fakes

final class FakeContainerEngine: ContainerEngine, @unchecked Sendable {
    var listResult: [Container] = []
    var listError: Error?
    var memory: [String: UInt64] = [:]
    var cpu: [String: UInt64] = [:]
    var detailResult: ContainerDetail?
    var detailError: Error?
    var actionError: Error?           // thrown by start/stop/restart/delete
    private(set) var started: [String] = []
    private(set) var stopped: [String] = []
    private(set) var restarted: [String] = []
    private(set) var deleted: [String] = []

    func list() async throws -> [Container] {
        if let listError { throw listError }
        return listResult
    }
    func start(id: String) async throws { if let actionError { throw actionError }; started.append(id) }
    func stop(id: String) async throws { if let actionError { throw actionError }; stopped.append(id) }
    func restart(id: String) async throws { if let actionError { throw actionError }; restarted.append(id) }
    func delete(id: String) async throws { if let actionError { throw actionError }; deleted.append(id) }
    func memoryUsage(id: String) async -> UInt64? { memory[id] }
    func cpuUsage(id: String) async -> UInt64? { cpu[id] }
    func detail(id: String) async throws -> ContainerDetail {
        if let detailError { throw detailError }
        return detailResult ?? ContainerDetail(id: id, image: "img", command: "", env: [], ports: [], mounts: [], startedAt: nil)
    }
}

final class FakeService: ServiceHealthChecking, @unchecked Sendable {
    var value: ServiceStatus
    var startError: Error?
    var stopError: Error?
    init(_ v: ServiceStatus) { value = v }
    func status() async -> ServiceStatus { value }
    func start() async throws { if let startError { throw startError }; value = .running }
    func stop() async throws { if let stopError { throw stopError }; value = .stopped }
}

final class FakeCompose: ComposeEngine, @unchecked Sendable {
    var available = true
    var upError: Error?
    private(set) var upped: [URL] = []
    private(set) var downed: [URL] = []
    var isAvailable: Bool { available }
    func up(file: URL) async throws { if let upError { throw upError }; upped.append(file) }
    func down(file: URL) async throws { downed.append(file) }
}

final class FakeCreator: ContainerCreating, @unchecked Sendable {
    var error: Error?
    private(set) var created: [NewContainerSpec] = []
    func create(_ spec: NewContainerSpec) async throws { if let error { throw error }; created.append(spec) }
}

final class FakeImages: ImageEngine, @unchecked Sendable {
    var listResult: [ContainerImage] = []
    var listError: Error?
    var pullError: Error?
    var deleteError: Error?
    private(set) var pulled: [String] = []
    private(set) var deleted: [String] = []
    func list() async throws -> [ContainerImage] { if let listError { throw listError }; return listResult }
    func pull(reference: String) async throws { if let pullError { throw pullError }; pulled.append(reference) }
    func delete(reference: String) async throws { if let deleteError { throw deleteError }; deleted.append(reference) }
}

final class FakeInfra: InfraEngine, @unchecked Sendable {
    var nets: [ContainerNetwork] = []
    var vols: [ContainerVolume] = []
    var listError: Error?
    var mutateError: Error?           // thrown by create/delete network/volume
    private(set) var createdNetworks: [String] = []
    private(set) var deletedNetworks: [String] = []
    private(set) var createdVolumes: [String] = []
    private(set) var deletedVolumes: [String] = []
    func listNetworks() async throws -> [ContainerNetwork] { if let listError { throw listError }; return nets }
    func createNetwork(name: String) async throws { if let mutateError { throw mutateError }; createdNetworks.append(name) }
    func deleteNetwork(id: String) async throws { if let mutateError { throw mutateError }; deletedNetworks.append(id) }
    func listVolumes() async throws -> [ContainerVolume] { if let listError { throw listError }; return vols }
    func createVolume(name: String) async throws { if let mutateError { throw mutateError }; createdVolumes.append(name) }
    func deleteVolume(name: String) async throws { if let mutateError { throw mutateError }; deletedVolumes.append(name) }
}

// MARK: - Helpers

@MainActor
private func makeState(
    container: FakeContainerEngine = FakeContainerEngine(),
    service: FakeService = FakeService(.running),
    compose: FakeCompose = FakeCompose(),
    creator: FakeCreator = FakeCreator(),
    images: FakeImages = FakeImages(),
    infra: FakeInfra = FakeInfra()
) -> AppState {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("consai-appstate-\(UUID().uuidString)", isDirectory: true)
    UserDefaults.standard.removeObject(forKey: "groupByNamePrefix")
    return AppState(containerEngine: container, composeEngine: compose, serviceHealth: service,
                    creator: creator, imageEngine: images, infraEngine: infra,
                    store: RegistryStore(directory: tmp), autostart: false)
}

private func ctr(_ id: String, _ status: ContainerStatus = .running, labels: [String: String] = [:]) -> Container {
    Container(id: id, name: id, image: "img", status: status, labels: labels)
}

// MARK: - Tests

@MainActor
@Suite struct AppStateRefreshTests {
    @Test func runningServiceListsAndAssembles() async {
        let engine = FakeContainerEngine()
        engine.listResult = [ctr("web"), ctr("db")]
        let state = makeState(container: engine)
        await state.refresh()
        #expect(state.serviceStatus == .running)
        #expect(state.containers.count == 2)
        #expect(state.standalone.count == 2)   // no labels, inference off → standalone
        #expect(state.runningCount == 2)
    }

    @Test func stoppedServiceClearsList() async {
        let engine = FakeContainerEngine(); engine.listResult = [ctr("web")]
        let state = makeState(container: engine, service: FakeService(.stopped))
        await state.refresh()
        #expect(state.containers.isEmpty)
        #expect(!state.isServiceRunning)
    }

    @Test func unknownServiceStillLists() async {
        let engine = FakeContainerEngine(); engine.listResult = [ctr("web")]
        let state = makeState(container: engine, service: FakeService(.unknown))
        await state.refresh()
        #expect(state.containers.count == 1)   // .unknown still attempts a list
    }

    @Test func listErrorSurfacesMessage() async {
        let engine = FakeContainerEngine(); engine.listError = ConsaiError.sdk("boom")
        let state = makeState(container: engine)
        await state.refresh()
        #expect(state.lastError == "boom")
    }

    @Test func fillsAndCarriesVitals() async {
        let engine = FakeContainerEngine()
        engine.listResult = [ctr("web")]
        engine.memory = ["web": 100 * 1_048_576]
        let state = makeState(container: engine)
        await state.refresh()
        #expect(state.containers.first?.memoryBytes == 100 * 1_048_576)
        // Next list omits memory; AppState carries the last-known value.
        engine.memory = [:]
        await state.refresh()
        #expect(state.containers.first?.memoryBytes == 100 * 1_048_576)
    }

    @Test func groupsByComposeLabel() async {
        let engine = FakeContainerEngine()
        let lbl = ProjectRegistry.composeProjectLabel
        engine.listResult = [ctr("shop-a", labels: [lbl: "shop"]), ctr("shop-b", labels: [lbl: "shop"]), ctr("lonely")]
        let state = makeState(container: engine)
        await state.refresh()
        #expect(state.stacks.count == 1)
        #expect(state.stacks.first?.projectName == "shop")
        #expect(state.standalone.map(\.name) == ["lonely"])
    }
}

@MainActor
@Suite struct AppStateActionTests {
    @Test func stopReconcilesToEngineState() async {
        let engine = FakeContainerEngine()
        engine.listResult = [ctr("web", .running)]
        let state = makeState(container: engine)
        await state.refresh()
        engine.listResult = [ctr("web", .stopped)]   // engine reports stopped after the action
        await state.stop("web")
        #expect(engine.stopped == ["web"])
        #expect(state.containers.first?.status == .stopped)
        #expect(state.inFlight.isEmpty)
    }

    @Test func deleteCallsEngineAndRefreshes() async {
        let engine = FakeContainerEngine()
        engine.listResult = [ctr("web")]
        let state = makeState(container: engine)
        await state.refresh()
        engine.listResult = []
        await state.delete("web")
        #expect(engine.deleted == ["web"])
        #expect(state.containers.isEmpty)
    }

    @Test func createReturnsTrueAndFalse() async {
        let creator = FakeCreator()
        let state = makeState(creator: creator)
        let ok = await state.create(NewContainerSpec(image: "redis"))
        #expect(ok)
        #expect(creator.created.count == 1)

        creator.error = ConsaiError.processFailed(stderr: "bad image")
        let state2 = makeState(creator: creator)
        let ok2 = await state2.create(NewContainerSpec(image: "nope"))
        #expect(!ok2)
        #expect(state2.lastError == "bad image")
    }
}

@MainActor
@Suite struct AppStateComposeTests {
    @Test func composeUpRecordsProjectAndDownGates() async {
        let engine = FakeContainerEngine()
        let compose = FakeCompose()
        let state = makeState(container: engine, compose: compose)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("proj-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("docker-compose.yml")
        try? "services: {}".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        await state.composeUp(file: file)
        #expect(compose.upped == [file])

        // down without a linked file → error, no call
        await state.composeDown(Stack(projectName: "x", services: [], origin: .inferred))
        #expect(state.lastError?.contains("No compose file") == true)
        #expect(compose.downed.isEmpty)
    }

    @Test func composeUnavailableReflected() async {
        let compose = FakeCompose(); compose.available = false
        let state = makeState(compose: compose)
        #expect(!state.composeAvailable)
    }
}

@MainActor
@Suite struct AppStateImageInfraTests {
    @Test func loadsPullsDeletesImages() async {
        let images = FakeImages()
        images.listResult = [ContainerImage(reference: "nginx:latest", digest: "sha256:a")]
        let state = makeState(images: images)
        await state.loadImages()
        #expect(state.images.count == 1)

        let ok = await state.pullImage("redis:7")
        #expect(ok)
        #expect(images.pulled == ["redis:7"])

        await state.deleteImage("nginx:latest")
        #expect(images.deleted == ["nginx:latest"])
    }

    @Test func pullErrorReturnsFalse() async {
        let images = FakeImages(); images.pullError = ConsaiError.processFailed(stderr: "no such image")
        let state = makeState(images: images)
        let ok = await state.pullImage("ghost")
        #expect(!ok)
        #expect(state.lastError == "no such image")
    }

    @Test func loadsAndMutatesInfra() async {
        let infra = FakeInfra()
        infra.nets = [ContainerNetwork(name: "default", subnet: "10.0.0.0/24")]
        infra.vols = [ContainerVolume(name: "pg", driver: "local", source: "/v/pg")]
        let state = makeState(infra: infra)
        await state.loadInfra()
        #expect(state.networks.count == 1)
        #expect(state.volumes.count == 1)

        await state.createNetwork("backend")
        #expect(infra.createdNetworks == ["backend"])
        await state.deleteVolume("pg")
        #expect(infra.deletedVolumes == ["pg"])
    }

    @Test func detailReturnsMappedValue() async {
        let engine = FakeContainerEngine()
        engine.detailResult = ContainerDetail(id: "web", image: "nginx", command: "nginx", env: ["A=1"], ports: [], mounts: [], startedAt: nil)
        let state = makeState(container: engine)
        let d = await state.detail("web")
        #expect(d?.image == "nginx")
        #expect(d?.env == ["A=1"])
    }
}

@MainActor
@Suite struct AppStateMiscTests {
    @Test func menuBarSymbolReflectsService() async {
        let running = makeState(service: FakeService(.running)); await running.refresh()
        #expect(running.menuBarSymbol == "leaf.fill")
        let stopped = makeState(service: FakeService(.stopped)); await stopped.refresh()
        #expect(stopped.menuBarSymbol == "exclamationmark.triangle.fill")
        let unknown = makeState(service: FakeService(.unknown)); await unknown.refresh()
        #expect(unknown.menuBarSymbol == "leaf")
    }

    @Test func clearErrorResets() {
        let state = makeState()
        state.lastError = "x"
        state.clearError()
        #expect(state.lastError == nil)
    }
}

@MainActor
@Suite struct ProjectNameTests {
    @Test func sanitizesDottedDirectoryName() {
        let url = URL(fileURLWithPath: "/Users/me/my.app/docker-compose.yml")
        #expect(AppState.projectName(for: url) == "my_app")
    }

    @Test func readsNameFieldWithCommentAndQuotes() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pn-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("docker-compose.yml")

        try? "name: shop   # the project\nservices: {}".write(to: file, atomically: true, encoding: .utf8)
        #expect(AppState.composeProjectName(in: file) == "shop")

        try? "name: \"my#app\"\nservices: {}".write(to: file, atomically: true, encoding: .utf8)
        #expect(AppState.composeProjectName(in: file) == "my#app")   // '#' inside quotes is not a comment
    }
}

// MARK: - Error paths

@MainActor
@Suite struct AppStateErrorTests {
    @Test func startStopRestartSurfaceEngineErrors() async {
        let engine = FakeContainerEngine()
        engine.listResult = [ctr("web")]
        let state = makeState(container: engine)
        await state.refresh()
        engine.actionError = ConsaiError.sdk("daemon refused")

        await state.start("web")
        #expect(state.lastError == "daemon refused")
        #expect(state.inFlight.isEmpty)          // act() always clears in-flight

        state.clearError()
        await state.restart("web")
        #expect(state.lastError == "daemon refused")

        state.clearError()
        await state.stop("web")
        #expect(state.lastError == "daemon refused")

        state.clearError()
        await state.delete("web")
        #expect(state.lastError == "daemon refused")
    }

    @Test func startStopServiceSucceedAndSurfaceErrors() async {
        let service = FakeService(.stopped)
        let state = makeState(service: service)
        await state.startService()
        #expect(service.value == .running)       // start() flipped it
        #expect(state.lastError == nil)

        await state.stopService()
        #expect(service.value == .stopped)

        service.startError = ConsaiError.sdk("launchd busy")
        await state.startService()
        #expect(state.lastError == "launchd busy")

        state.clearError()
        service.stopError = ConsaiError.sdk("still draining")
        await state.stopService()
        #expect(state.lastError == "still draining")
    }

    @Test func loadImagesAndDeleteImageSurfaceErrors() async {
        let images = FakeImages(); images.listError = ConsaiError.processFailed(stderr: "list failed")
        let state = makeState(images: images)
        await state.loadImages()
        #expect(state.lastError == "list failed")
        #expect(state.images.isEmpty)

        state.clearError()
        images.listError = nil
        images.deleteError = ConsaiError.processFailed(stderr: "in use")
        await state.deleteImage("nginx:latest")
        #expect(state.lastError == "in use")
    }

    @Test func loadInfraSurfacesError() async {
        let infra = FakeInfra(); infra.listError = ConsaiError.sdk("no daemon")
        let state = makeState(infra: infra)
        await state.loadInfra()
        #expect(state.lastError == "no daemon")
    }

    @Test func infraMutationsSucceedAndSurfaceErrors() async {
        let infra = FakeInfra()
        let state = makeState(infra: infra)
        await state.deleteNetwork("backend")
        #expect(infra.deletedNetworks == ["backend"])
        await state.createVolume("pgdata")
        #expect(infra.createdVolumes == ["pgdata"])

        infra.mutateError = ConsaiError.processFailed(stderr: "network busy")
        await state.createNetwork("frontend")
        #expect(state.lastError == "network busy")
    }

    @Test func composeUpErrorSurfacesAndDoesNotRecord() async {
        let compose = FakeCompose(); compose.upError = ConsaiError.composeMissing
        let state = makeState(compose: compose)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cu-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("docker-compose.yml")
        try? "services: {}".write(to: file, atomically: true, encoding: .utf8)

        await state.composeUp(file: file)
        #expect(state.lastError != nil)
        #expect(compose.upped.isEmpty)
        #expect(state.recentComposeFiles.isEmpty)   // failed up does not get recorded
    }

    @Test func composeDownRunsWhenFileLinked() async {
        let compose = FakeCompose()
        let state = makeState(compose: compose)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("docker-compose.yml")
        try? "services: {}".write(to: file, atomically: true, encoding: .utf8)

        let stack = Stack(projectName: "shop", composeFilePath: file.path, services: [], origin: .launchedByConsai)
        await state.composeDown(stack)
        #expect(compose.downed == [file])
        #expect(state.lastError == nil)
    }

    @Test func detailErrorReturnsNil() async {
        let engine = FakeContainerEngine(); engine.detailError = ConsaiError.sdk("gone")
        let state = makeState(container: engine)
        let d = await state.detail("web")
        #expect(d == nil)
        #expect(state.lastError == "gone")
    }
}

// MARK: - Registry & lifecycle

@MainActor
@Suite struct AppStateLifecycleTests {
    // Uses a compose-LABELED stack (always grouped, no global UserDefaults flag) so the test
    // is immune to the parallel-test race on `groupByNamePrefix` in UserDefaults.standard.
    @Test func linkAndForgetToggleComposeFilePath() async {
        let engine = FakeContainerEngine()
        let lbl = ProjectRegistry.composeProjectLabel
        engine.listResult = [ctr("shop-api", labels: [lbl: "shop"]), ctr("shop-web", labels: [lbl: "shop"])]
        let state = makeState(container: engine)
        await state.refresh()
        #expect(state.stacks.first?.origin == .composeLabeled)
        #expect(state.stacks.first?.composeFilePath == nil)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lk-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("docker-compose.yml")
        try? "services: {}".write(to: file, atomically: true, encoding: .utf8)

        state.linkComposeFile(project: "shop", file: file)
        #expect(state.stacks.first?.composeFilePath == file.path)   // registry path now attached

        state.forgetStack("shop")
        #expect(state.stacks.first?.composeFilePath == nil)         // path dropped on forget
    }

    @Test func setPanelVisibleTriggersRefresh() async {
        let engine = FakeContainerEngine(); engine.listResult = [ctr("web")]
        let state = makeState(container: engine)
        state.setPanelVisible(true)          // schedules an async refresh
        // The refresh is fire-and-forget; yield until it lands.
        for _ in 0..<50 where state.containers.isEmpty { await Task.yield() }
        #expect(state.containers.count == 1)
        state.setPanelVisible(false)         // exercises the no-refresh branch
    }

    @Test func startPollingIsIdempotentAndStops() async {
        let state = makeState()
        state.startPolling()
        state.startPolling()   // second call is a no-op (guard)
        state.stopPolling()    // tears down cleanly
    }

    @Test func storedPathTreatsEmptyAsNil() {
        let key = "consai-test-path-\(UUID().uuidString)"
        #expect(AppState.storedPath(key) == nil)
        UserDefaults.standard.set("", forKey: key)
        #expect(AppState.storedPath(key) == nil)
        UserDefaults.standard.set("/usr/local/bin/container", forKey: key)
        #expect(AppState.storedPath(key) == "/usr/local/bin/container")
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Value-type models

@Suite struct ModelValueTests {
    @Test func portAndMountBindingIdentity() {
        let p = PortBinding(host: 8080, container: 80, proto: "tcp")
        #expect(p.id == "8080:80/tcp")
        let m = MountBinding(source: "/host", destination: "/data")
        #expect(m.id == "/host->/data")
    }

    @Test func networkAndVolumeIdentity() {
        #expect(ContainerNetwork(name: "default", subnet: "10.0.0.0/24").id == "default")
        let v = ContainerVolume(name: "pg", driver: "local", source: "/v/pg")
        #expect(v.id == "pg")
        #expect(v.driver == "local")
    }

    @Test func stackCountsReflectServiceStatuses() {
        let stack = Stack(projectName: "shop",
                          services: [ctr("a", .running), ctr("b", .running), ctr("c", .stopped)],
                          origin: .composeLabeled)
        #expect(stack.total == 3)
        #expect(stack.runningCount == 2)
        #expect(stack.id == "shop")
    }

    @Test func cpuPercentGuardsBadSamples() {
        #expect(cpuPercent(previousUsec: 0, currentUsec: 1_000_000, elapsedSeconds: 1) == 100)
        #expect(cpuPercent(previousUsec: 0, currentUsec: 0, elapsedSeconds: 0) == nil)        // no elapsed
        #expect(cpuPercent(previousUsec: 100, currentUsec: 50, elapsedSeconds: 1) == nil)     // counter reset
    }
}

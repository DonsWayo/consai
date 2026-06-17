import Foundation
import Observation
import ConsaiCore

/// The single source of truth for the UI. Owns the engines, polls for container/service
/// state, folds containers into stacks, and applies optimistic updates on actions.
@MainActor
@Observable
final class AppState {
    private(set) var containers: [Container] = []
    private(set) var stacks: [Stack] = []
    private(set) var standalone: [Container] = []
    private(set) var serviceStatus: ServiceStatus = .unknown
    /// Container ids / project names with an action in flight (drives spinners / disabling).
    private(set) var inFlight: Set<String> = []
    var lastError: String?

    private let containerEngine: ContainerEngine
    private let composeEngine: ComposeEngine
    private let serviceHealth: ServiceHealthChecking
    private let store: RegistryStore
    private var registry: ProjectRegistry
    private var pollTask: Task<Void, Never>?
    private var panelVisible = false

    var runningCount: Int { containers.filter { $0.status == .running }.count }
    var isServiceRunning: Bool { serviceStatus == .running }
    var composeAvailable: Bool { composeEngine.isAvailable }
    var recentComposeFiles: [URL] { registry.recentComposeFiles }

    var menuBarSymbol: String {
        switch serviceStatus {
        case .running: return "shippingbox.fill"
        case .stopped: return "exclamationmark.triangle.fill"
        case .unknown: return "shippingbox"
        }
    }

    init(
        containerEngine: ContainerEngine = SDKContainerEngine(),
        composeEngine: ComposeEngine = CLIComposeEngine(),
        serviceHealth: ServiceHealthChecking = CLIServiceHealth(),
        store: RegistryStore = RegistryStore()
    ) {
        self.containerEngine = containerEngine
        self.composeEngine = composeEngine
        self.serviceHealth = serviceHealth
        self.store = store
        self.registry = store.load()
        startPolling()
    }

    // MARK: - Polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let fast = self?.panelVisible ?? false
                try? await Task.sleep(for: .seconds(fast ? 2 : 15))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { Task { await refresh() } }
    }

    func refresh() async {
        serviceStatus = await serviceHealth.status()
        guard serviceStatus == .running else {
            containers = []
            reassemble()
            return
        }
        do {
            containers = try await containerEngine.list()
            reassemble()
        } catch {
            lastError = describe(error)
        }
    }

    /// Recompute stacks + standalone from the current container list and known projects.
    private func reassemble() {
        let result = registry.assemble(containers: containers)
        stacks = result.stacks
        standalone = result.standalone
    }

    // MARK: - Container actions

    func start(_ id: String) async { await act(id, optimistic: .starting) { try await self.containerEngine.start(id: id) } }
    func stop(_ id: String) async { await act(id, optimistic: .stopping) { try await self.containerEngine.stop(id: id) } }
    func restart(_ id: String) async { await act(id, optimistic: .starting) { try await self.containerEngine.restart(id: id) } }

    func delete(_ id: String) async {
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        do {
            try await containerEngine.delete(id: id)
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    // MARK: - Stack actions

    /// Bring a compose stack up. Records the project so future polls group it as known.
    func composeUp(file: URL) async {
        let project = Self.projectName(for: file)
        inFlight.insert(project)
        defer { inFlight.remove(project) }
        do {
            try await composeEngine.up(file: file)
            registry.record(project: project, composeFile: file)
            persist()
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    /// Bring a known stack down. Gated on a linked compose file — never guesses.
    func composeDown(_ stack: Stack) async {
        guard let path = stack.composeFilePath else {
            lastError = "No compose file linked for \(stack.projectName). Link one first."
            return
        }
        inFlight.insert(stack.projectName)
        defer { inFlight.remove(stack.projectName) }
        do {
            try await composeEngine.down(file: URL(fileURLWithPath: path))
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    /// Promote an inferred stack to known by pointing it at its compose file.
    func linkComposeFile(project: String, file: URL) {
        registry.record(project: project, composeFile: file)
        persist()
        reassemble()
    }

    func forgetStack(_ project: String) {
        registry.remove(project: project)
        persist()
        reassemble()
    }

    func startService() async {
        do {
            try await serviceHealth.start()
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    func clearError() { lastError = nil }

    // MARK: - Helpers

    private func act(_ id: String, optimistic: ContainerStatus, _ op: @escaping () async throws -> Void) async {
        inFlight.insert(id)
        if let idx = containers.firstIndex(where: { $0.id == id }) {
            containers[idx].status = optimistic
            reassemble()
        }
        defer { inFlight.remove(id) }
        do {
            try await op()
        } catch {
            lastError = describe(error)
        }
        await refresh()
    }

    private func persist() { try? store.save(registry) }

    /// Project name follows `container-compose`'s rule: the compose file's directory name.
    /// (`container-compose` also honors a `name:` field; we approximate with the dir name,
    /// which is its fallback and the common case.)
    static func projectName(for composeFile: URL) -> String {
        composeFile.deletingLastPathComponent().lastPathComponent
    }

    private func describe(_ error: Error) -> String {
        guard let consai = error as? ConsaiError else { return "\(error)" }
        switch consai {
        case .serviceDown: return "Container service is not running."
        case .composeMissing: return "container-compose is not installed."
        case .processFailed(let stderr): return stderr.isEmpty ? "Command failed." : stderr
        case .sdk(let message): return message
        }
    }
}

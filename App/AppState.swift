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
    private let creator: ContainerCreating
    private let store: RegistryStore
    private var registry: ProjectRegistry
    private var pollTask: Task<Void, Never>?
    private var panelVisible = false
    private var sampler = VitalsSampler()

    var runningCount: Int { containers.filter { $0.status == .running }.count }
    var isServiceRunning: Bool { serviceStatus == .running }
    var composeAvailable: Bool { composeEngine.isAvailable }
    var recentComposeFiles: [URL] { registry.recentComposeFiles }

    var menuBarSymbol: String {
        switch serviceStatus {
        case .running: return "leaf.fill"
        case .stopped: return "exclamationmark.triangle.fill"
        case .unknown: return "leaf"
        }
    }

    init(
        containerEngine: ContainerEngine = SDKContainerEngine(),
        composeEngine: ComposeEngine = CLIComposeEngine(),
        serviceHealth: ServiceHealthChecking = CLIServiceHealth(),
        creator: ContainerCreating = CLIContainerCreator(),
        store: RegistryStore = RegistryStore()
    ) {
        self.containerEngine = containerEngine
        self.composeEngine = composeEngine
        self.serviceHealth = serviceHealth
        self.creator = creator
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
                let defaults = UserDefaults.standard
                let open = defaults.object(forKey: "pollOpen") as? Double ?? 2
                let closed = defaults.object(forKey: "pollClosed") as? Double ?? 15
                try? await Task.sleep(for: .seconds(fast ? open : closed))
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
        // Only a definite "stopped" clears the list. On `.unknown` we still try to list
        // (the status wording just wasn't recognized); a real failure surfaces as an error.
        if serviceStatus == .stopped {
            containers = []
            reassemble()
            return
        }
        do {
            let fresh = try await containerEngine.list()
            // Preserve an in-flight container's optimistic status so a poll mid-action
            // doesn't flicker it back to the pre-action state. Carry over last-known memory
            // so vitals don't blink to empty between fetches.
            // Carry last-known vitals so they don't blink to empty between fetches.
            let priorMemory = Dictionary(containers.map { ($0.id, $0.memoryBytes) }, uniquingKeysWith: { a, _ in a })
            let priorCPU = Dictionary(containers.map { ($0.id, $0.cpuPercent) }, uniquingKeysWith: { a, _ in a })
            containers = fresh.map { incoming in
                var c = incoming
                if c.memoryBytes == nil { c.memoryBytes = priorMemory[incoming.id] ?? nil }
                if c.cpuPercent == nil { c.cpuPercent = priorCPU[incoming.id] ?? nil }
                if inFlight.contains(incoming.id),
                   let existing = containers.first(where: { $0.id == incoming.id }) {
                    c.status = existing.status
                }
                return c
            }
            reassemble()
            await fetchVitals()
        } catch {
            lastError = describe(error)
        }
    }

    /// Concurrently fetch live memory + CPU for running containers, then re-assemble.
    /// Best-effort: missing values leave the carried-over value in place.
    private func fetchVitals() async {
        let engine = containerEngine
        let running = containers.filter { $0.status == .running }.map(\.id)
        sampler.retain(ids: Set(running))
        guard !running.isEmpty else { return }

        let results = await withTaskGroup(of: (String, UInt64?, UInt64?).self) { group -> [(String, UInt64?, UInt64?)] in
            for id in running {
                group.addTask { (id, await engine.memoryUsage(id: id), await engine.cpuUsage(id: id)) }
            }
            var out: [(String, UInt64?, UInt64?)] = []
            for await r in group { out.append(r) }
            return out
        }

        let now = Date()
        for (id, mem, cpuUsec) in results {
            guard let idx = containers.firstIndex(where: { $0.id == id }) else { continue }
            if let mem { containers[idx].memoryBytes = mem }
            if let cpuUsec, let pct = sampler.recordCPU(id: id, cumulativeUsec: cpuUsec, at: now) {
                containers[idx].cpuPercent = pct
            }
        }
        reassemble()
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

    func stopService() async {
        do {
            try await serviceHealth.stop()
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    /// Create + run a new container. Returns true on success (so the window can close).
    func create(_ spec: NewContainerSpec) async -> Bool {
        do {
            try await creator.create(spec)
            await refresh()
            return true
        } catch {
            lastError = describe(error)
            return false
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
        do {
            try await op()
        } catch {
            lastError = describe(error)
        }
        // Clear in-flight BEFORE the reconciling refresh, so the refresh shows the real
        // post-action status instead of preserving the now-stale optimistic value.
        inFlight.remove(id)
        await refresh()
    }

    private func persist() {
        do {
            try store.save(registry)
        } catch {
            lastError = "Couldn't save project registry: \(error.localizedDescription)"
        }
    }

    /// Project name, matching `container-compose`: the compose file's top-level `name:`
    /// field if present, else the directory name — with `.`→`_` sanitization either way
    /// (so `~/my.app/compose.yml` groups as `my_app-<service>`).
    static func projectName(for composeFile: URL) -> String {
        if let explicit = composeProjectName(in: composeFile) { return sanitizeProjectName(explicit) }
        return sanitizeProjectName(composeFile.deletingLastPathComponent().lastPathComponent)
    }

    static func sanitizeProjectName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "_")
    }

    /// Best-effort scan for a top-level `name:` key in a compose file.
    static func composeProjectName(in file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = line.first, first != " ", first != "\t" else { continue } // top-level only
            guard let range = line.range(of: #"^name:\s*"#, options: .regularExpression) else { continue }
            var value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                // Quoted scalar: take inner content verbatim ('#' inside is not a comment).
                let inner = value.dropFirst()
                if let close = inner.firstIndex(of: quote) {
                    value = String(inner[..<close])
                } else {
                    value = String(inner)
                }
            } else {
                // Unquoted: a comment starts only at whitespace-then-'#'.
                if let comment = value.range(of: #"\s#"#, options: .regularExpression) {
                    value = String(value[..<comment.lowerBound])
                }
                value = value.trimmingCharacters(in: .whitespaces)
            }
            if !value.isEmpty { return value }
        }
        return nil
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

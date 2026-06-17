import Foundation
import Observation
import ConsaiCore

/// The single source of truth for the UI. Owns the engines, polls for container/service
/// state, folds containers into stacks, and applies optimistic updates on actions.
///
/// Lives in `ConsaiKit` (not the app executable) so its orchestration logic is unit-testable
/// with injected mock engines.
@MainActor
@Observable
public final class AppState {
    public private(set) var containers: [Container] = []
    public private(set) var stacks: [Stack] = []
    public private(set) var standalone: [Container] = []
    public private(set) var serviceStatus: ServiceStatus = .unknown
    /// Container ids / project names with an action in flight (drives spinners / disabling).
    public private(set) var inFlight: Set<String> = []
    public var lastError: String?

    public private(set) var images: [ContainerImage] = []
    public private(set) var networks: [ContainerNetwork] = []
    public private(set) var volumes: [ContainerVolume] = []

    private let containerEngine: ContainerEngine
    private let composeEngine: ComposeEngine
    private let serviceHealth: ServiceHealthChecking
    private let creator: ContainerCreating
    private let imageEngine: ImageEngine
    private let infraEngine: InfraEngine
    private let store: RegistryStore
    private var registry: ProjectRegistry
    private var pollTask: Task<Void, Never>?
    private var panelVisible = false
    private var sampler = VitalsSampler()

    public var runningCount: Int { containers.filter { $0.status == .running }.count }
    public var isServiceRunning: Bool { serviceStatus == .running }
    public var composeAvailable: Bool { composeEngine.isAvailable }
    public var recentComposeFiles: [URL] { registry.recentComposeFiles }

    public var menuBarSymbol: String {
        switch serviceStatus {
        case .running: return "leaf.fill"
        case .stopped: return "exclamationmark.triangle.fill"
        case .unknown: return "leaf"
        }
    }

    /// A user-configured binary path from settings, or nil to auto-detect (empty = auto).
    public static func storedPath(_ key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)
        return (value?.isEmpty == false) ? value : nil
    }

    /// - Parameter autostart: begin polling on init (false in tests for deterministic control).
    public init(
        containerEngine: ContainerEngine = SDKContainerEngine(),
        composeEngine: ComposeEngine = CLIComposeEngine(binaryPath: AppState.storedPath("composeBinaryPath")),
        serviceHealth: ServiceHealthChecking = CLIServiceHealth(binaryPath: AppState.storedPath("containerBinaryPath")),
        creator: ContainerCreating = CLIContainerCreator(binaryPath: AppState.storedPath("containerBinaryPath")),
        imageEngine: ImageEngine = SDKImageEngine(binaryPath: AppState.storedPath("containerBinaryPath")),
        infraEngine: InfraEngine = SDKInfraEngine(binaryPath: AppState.storedPath("containerBinaryPath")),
        store: RegistryStore = RegistryStore(),
        autostart: Bool = true
    ) {
        self.containerEngine = containerEngine
        self.composeEngine = composeEngine
        self.serviceHealth = serviceHealth
        self.creator = creator
        self.imageEngine = imageEngine
        self.infraEngine = infraEngine
        self.store = store
        self.registry = store.load()
        if autostart { startPolling() }
    }

    // MARK: - Polling

    public func startPolling() {
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

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { Task { await refresh() } }
    }

    public func refresh() async {
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
            // Preserve an in-flight container's optimistic status so a poll mid-action doesn't
            // flicker it back, and carry last-known vitals so they don't blink between fetches.
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
    /// Name-prefix inference for externally-launched containers is opt-in (default off) so
    /// unrelated containers that merely share a prefix aren't grouped into a fake stack (#12).
    private func reassemble() {
        let infer = UserDefaults.standard.bool(forKey: "groupByNamePrefix")
        let result = registry.assemble(containers: containers, inferStacks: infer)
        stacks = result.stacks
        standalone = result.standalone
    }

    // MARK: - Container actions

    public func start(_ id: String) async { await act(id, optimistic: .starting) { try await self.containerEngine.start(id: id) } }
    public func stop(_ id: String) async { await act(id, optimistic: .stopping) { try await self.containerEngine.stop(id: id) } }
    public func restart(_ id: String) async { await act(id, optimistic: .starting) { try await self.containerEngine.restart(id: id) } }

    public func delete(_ id: String) async {
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
    public func composeUp(file: URL) async {
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
    public func composeDown(_ stack: Stack) async {
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
    public func linkComposeFile(project: String, file: URL) {
        registry.record(project: project, composeFile: file)
        persist()
        reassemble()
    }

    public func forgetStack(_ project: String) {
        registry.remove(project: project)
        persist()
        reassemble()
    }

    public func startService() async {
        do {
            try await serviceHealth.start()
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    public func stopService() async {
        do {
            try await serviceHealth.stop()
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    /// Create + run a new container. Returns true on success (so the window can close).
    public func create(_ spec: NewContainerSpec) async -> Bool {
        do {
            try await creator.create(spec)
            await refresh()
            return true
        } catch {
            lastError = describe(error)
            return false
        }
    }

    public func clearError() { lastError = nil }

    // MARK: - Images

    public func loadImages() async {
        do { images = try await imageEngine.list() }
        catch { lastError = describe(error) }
    }

    /// Pull an image; returns true on success. Refreshes the image list.
    public func pullImage(_ reference: String) async -> Bool {
        do {
            try await imageEngine.pull(reference: reference)
            await loadImages()
            return true
        } catch {
            lastError = describe(error)
            return false
        }
    }

    public func deleteImage(_ reference: String) async {
        do {
            try await imageEngine.delete(reference: reference)
            await loadImages()
        } catch {
            lastError = describe(error)
        }
    }

    // MARK: - Container detail / exec

    public func detail(_ id: String) async -> ContainerDetail? {
        do { return try await containerEngine.detail(id: id) }
        catch { lastError = describe(error); return nil }
    }

    /// Open an interactive shell into the container in Terminal.
    public func execShell(_ id: String) {
        let binary = AppState.storedPath("containerBinaryPath") ?? "/usr/local/bin/container"
        ContainerShell.openShell(binaryPath: binary, id: id)
    }

    // MARK: - Networks & volumes

    public func loadInfra() async {
        do {
            async let n = infraEngine.listNetworks()
            async let v = infraEngine.listVolumes()
            networks = try await n
            volumes = try await v
        } catch {
            lastError = describe(error)
        }
    }

    public func createNetwork(_ name: String) async { await infraOp { try await self.infraEngine.createNetwork(name: name) } }
    public func deleteNetwork(_ id: String) async { await infraOp { try await self.infraEngine.deleteNetwork(id: id) } }
    public func createVolume(_ name: String) async { await infraOp { try await self.infraEngine.createVolume(name: name) } }
    public func deleteVolume(_ name: String) async { await infraOp { try await self.infraEngine.deleteVolume(name: name) } }

    private func infraOp(_ op: @escaping () async throws -> Void) async {
        do { try await op(); await loadInfra() }
        catch { lastError = describe(error) }
    }

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

    /// Project name, matching `container-compose`: the compose file's top-level `name:` field
    /// if present, else the directory name — with `.`→`_` sanitization either way.
    public static func projectName(for composeFile: URL) -> String {
        if let explicit = composeProjectName(in: composeFile) { return sanitizeProjectName(explicit) }
        return sanitizeProjectName(composeFile.deletingLastPathComponent().lastPathComponent)
    }

    public static func sanitizeProjectName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "_")
    }

    /// Best-effort scan for a top-level `name:` key in a compose file.
    public static func composeProjectName(in file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = line.first, first != " ", first != "\t" else { continue } // top-level only
            guard let range = line.range(of: #"^name:\s*"#, options: .regularExpression) else { continue }
            var value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                let inner = value.dropFirst()
                if let close = inner.firstIndex(of: quote) {
                    value = String(inner[..<close])
                } else {
                    value = String(inner)
                }
            } else {
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

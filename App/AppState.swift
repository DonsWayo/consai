import Foundation
import Observation
import ConsaiCore

/// The single source of truth for the UI. Owns the engines, polls for container/service
/// state, and applies optimistic updates on actions. All UI renders from here.
@MainActor
@Observable
final class AppState {
    private(set) var containers: [Container] = []
    private(set) var serviceStatus: ServiceStatus = .unknown
    /// Container ids with an action currently in flight (drives row spinners / disabling).
    private(set) var inFlight: Set<String> = []
    var lastError: String?

    private let containerEngine: ContainerEngine
    private let serviceHealth: ServiceHealthChecking
    private var pollTask: Task<Void, Never>?
    private var panelVisible = false

    var runningCount: Int { containers.filter { $0.status == .running }.count }
    var isServiceRunning: Bool { serviceStatus == .running }

    /// Menu bar icon reflects service health at a glance.
    var menuBarSymbol: String {
        switch serviceStatus {
        case .running: return "shippingbox.fill"
        case .stopped: return "exclamationmark.triangle.fill"
        case .unknown: return "shippingbox"
        }
    }

    init(
        containerEngine: ContainerEngine = SDKContainerEngine(),
        serviceHealth: ServiceHealthChecking = CLIServiceHealth()
    ) {
        self.containerEngine = containerEngine
        self.serviceHealth = serviceHealth
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

    /// Called by the panel on appear/disappear to switch poll cadence and refresh promptly.
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { Task { await refresh() } }
    }

    func refresh() async {
        serviceStatus = await serviceHealth.status()
        guard serviceStatus == .running else {
            containers = []   // can't list while the service is down
            return
        }
        do {
            containers = try await containerEngine.list()
        } catch {
            lastError = describe(error)
        }
    }

    // MARK: - Actions

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

    func startService() async {
        do {
            try await serviceHealth.start()
            await refresh()
        } catch {
            lastError = describe(error)
        }
    }

    func clearError() { lastError = nil }

    /// Run an action with an optimistic local status, reverting via refresh on success or
    /// failure (the next list is authoritative either way).
    private func act(_ id: String, optimistic: ContainerStatus, _ op: @escaping () async throws -> Void) async {
        inFlight.insert(id)
        if let idx = containers.firstIndex(where: { $0.id == id }) {
            containers[idx].status = optimistic
        }
        defer { inFlight.remove(id) }
        do {
            try await op()
        } catch {
            lastError = describe(error)
        }
        await refresh()
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

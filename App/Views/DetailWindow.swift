import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// Per-container detail: image, command, started, env, ports, mounts; open a shell or logs.
/// Refreshes every 5 s while visible so status and vitals stay current.
struct DetailWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    let containerID: String

    @State private var detail: ContainerDetail?
    @State private var loading = true
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loading {
                    ProgressView().padding(24)
                } else if let detail {
                    statusRow
                    field("Image", detail.image)
                    field("Command", detail.command.isEmpty ? "—" : detail.command)
                    if let started = detail.startedAt {
                        field("Started", started.formatted(date: .abbreviated, time: .shortened))
                    }
                    listSection("ENVIRONMENT", detail.env.isEmpty ? ["—"] : detail.env)
                    listSection("PORTS", detail.ports.isEmpty ? ["—"] : detail.ports.map { "\($0.host) → \($0.container)/\($0.proto)" })
                    listSection("MOUNTS", detail.mounts.isEmpty ? ["—"] : detail.mounts.map { "\($0.source) → \($0.destination)" })
                } else {
                    EmptyState(symbol: "questionmark.circle", title: "No detail", subtitle: "Couldn't load this container.")
                }
            }
            .padding(.bottom, 10)
        }
        .frame(minWidth: 460, minHeight: 360)
        .consaiSurface()
        .preferredColorScheme(.dark).tint(Theme.jade)
        .navigationTitle(containerID)
        .toolbar {
            ToolbarItemGroup {
                Button { appState.execShell(containerID) } label: { Label("Shell", systemImage: "terminal") }
                Button { openWindow(id: "logs", value: containerID) } label: { Label("Logs", systemImage: "doc.text") }
            }
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            startRefreshing()
        }
        .onDisappear { stopRefreshing() }
    }

    /// Live status dot + container name, mirroring the panel ContainerRow look.
    @ViewBuilder
    private var statusRow: some View {
        if let container = appState.containers.first(where: { $0.id == containerID }) {
            HStack(spacing: 8) {
                StatusDot(status: container.status)
                Text(container.status.rawValue.capitalized)
                    .font(Theme.ui(12, .medium))
                    .foregroundStyle(container.status == .running ? Theme.jade : Theme.dim)
                if let mem = container.memoryBytes {
                    Spacer(minLength: 0)
                    Text(formatBytes(mem))
                        .font(Theme.mono(11)).foregroundStyle(Theme.dim2)
                }
                if let cpu = container.cpuPercent {
                    Text(String(format: "%.1f%%", cpu))
                        .font(Theme.mono(11)).foregroundStyle(Theme.dim2)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
        }
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                detail = await appState.detail(containerID)
                loading = false
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.sectionLabel).tracking(1.5).foregroundStyle(Theme.dim2)
            Text(value).font(Theme.mono(11)).foregroundStyle(Theme.text).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 7)
    }

    private func listSection(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.sectionLabel).tracking(1.5).foregroundStyle(Theme.dim2)
            ForEach(items, id: \.self) { item in
                Text(item).font(Theme.mono(11)).foregroundStyle(Theme.dim).textSelection(.enabled)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 7)
    }
}

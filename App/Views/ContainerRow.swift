import SwiftUI
import ConsaiCore

/// One container row (used standalone and inside a stack branch): living dot, name + image,
/// and IP/state vitals on the right; hover reveals quick actions.
struct ContainerRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    let container: Container
    @State private var hovering = false
    @State private var confirmingDelete = false

    private var busy: Bool { appState.inFlight.contains(container.id) }

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: container.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(container.name)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(container.status == .stopped ? Theme.dim : Theme.text)
                    .lineLimit(1)
                Text(container.image)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.dim2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if busy {
                ProgressView().controlSize(.small)
            } else if hovering {
                actions
            } else {
                vitals
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .confirmationDialog("Delete \(container.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { Task { await appState.delete(container.id) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var vitals: some View {
        switch container.status {
        case .running:
            HStack(spacing: 5) {
                if let ip = container.ipAddress {
                    Text(ip).font(Theme.mono(10)).foregroundStyle(Theme.ip)
                }
                if let mem = container.memoryBytes {
                    if container.ipAddress != nil { Text("·").font(Theme.mono(10)).foregroundStyle(Theme.dim2) }
                    Text(formatBytes(mem)).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                } else if container.ipAddress == nil {
                    Text("alive").font(Theme.mono(10)).foregroundStyle(Theme.jade)
                }
            }
        case .stopped:
            Text("resting").font(Theme.mono(10)).foregroundStyle(Theme.dim2)
        case .starting, .stopping:
            Text(container.status.rawValue).font(Theme.mono(10)).foregroundStyle(Theme.amber)
        case .unknown:
            Text("?").font(Theme.mono(10)).foregroundStyle(Theme.danger)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if container.status == .running {
            iconButton("stop.fill", "Stop") { Task { await appState.stop(container.id) } }
            iconButton("arrow.clockwise", "Restart") { Task { await appState.restart(container.id) } }
        } else {
            iconButton("play.fill", "Start") { Task { await appState.start(container.id) } }
        }
        iconButton("doc.text", "Logs") { openWindow(id: "logs", value: container.id) }
        iconButton("trash", "Delete") { confirmingDelete = true }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.dim)
        .help(help)
    }
}

/// A living status indicator — jade when alive, amber transitioning, dim at rest.
struct StatusDot: View {
    let status: ContainerStatus

    private var color: Color {
        switch status {
        case .running: return Theme.jade
        case .starting, .stopping: return Theme.amber
        case .stopped: return Theme.stopDot
        case .unknown: return Theme.danger
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle().fill(color.opacity(status == .running ? 0.18 : 0)).frame(width: 12, height: 12)
            )
            .help(status.rawValue)
    }
}

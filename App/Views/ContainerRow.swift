import SwiftUI
import ConsaiCore

/// One container row: status dot, name/image, and hover quick actions.
struct ContainerRow: View {
    @Environment(AppState.self) private var appState
    let container: Container
    @State private var hovering = false
    @State private var confirmingDelete = false

    private var busy: Bool { appState.inFlight.contains(container.id) }

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: container.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(container.name).font(.system(.body, design: .default)).lineLimit(1)
                Text(container.image).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()

            if busy {
                ProgressView().controlSize(.small)
            } else if hovering {
                actions
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .confirmationDialog("Delete \(container.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { Task { await appState.delete(container.id) } }
            Button("Cancel", role: .cancel) {}
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
        iconButton("trash", "Delete") { confirmingDelete = true }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }
}

/// Color-coded status indicator.
struct StatusDot: View {
    let status: ContainerStatus

    private var color: Color {
        switch status {
        case .running: return .green
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .unknown: return .red
        }
    }

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .help(status.rawValue)
    }
}

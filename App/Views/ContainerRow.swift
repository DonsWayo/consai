import SwiftUI
import ConsaiCore
import ConsaiKit

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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)  // keep vitals one line; image truncates
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.13), value: hovering)
        .onTapGesture { openWindow(id: "detail", value: container.id) }
        .help("Click for details")
        .confirmationDialog("Delete \(container.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { Task { await appState.delete(container.id) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var vitals: some View {
        switch container.status {
        case .running:
            let extras = [
                container.cpuPercent.map { "\(Int($0.rounded()))%" },
                container.memoryBytes.map(formatBytes),
            ].compactMap { $0 }
            if container.ipAddress == nil && extras.isEmpty {
                Text("alive").font(Theme.mono(10)).foregroundStyle(Theme.jade)
            } else {
                HStack(spacing: 4) {
                    if let ip = container.ipAddress {
                        Text(ip).font(Theme.mono(10)).foregroundStyle(Theme.ip)
                    }
                    ForEach(Array(extras.enumerated()), id: \.offset) { index, value in
                        if index > 0 || container.ipAddress != nil {
                            Text("·").font(Theme.mono(10)).foregroundStyle(Theme.dim2)
                        }
                        Text(value).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
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
        iconButton("info.circle", "Details") { openWindow(id: "detail", value: container.id) }
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

/// A living status indicator — jade when alive (a slow "breathing" aura), amber
/// transitioning, dim at rest. The breath is the panel's signature; it's the one place we
/// spend motion, and it's disabled under Reduce Motion.
struct StatusDot: View {
    let status: ContainerStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var color: Color {
        switch status {
        case .running: return Theme.jade
        case .starting, .stopping: return Theme.amber
        case .stopped: return Theme.stopDot
        case .unknown: return Theme.danger
        }
    }

    private var isAlive: Bool { status == .running }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .fill(color.opacity(isAlive ? 0.22 : 0))
                    .frame(width: 13, height: 13)
                    .scaleEffect(breathing ? 1.3 : 0.85)
                    .opacity(breathing ? 0.12 : 0.5)
            )
            .help(status.rawValue)
            .onAppear { updateBreathing() }
            .onChange(of: status) { _, _ in updateBreathing() }
            .onChange(of: reduceMotion) { _, _ in updateBreathing() }
    }

    private func updateBreathing() {
        guard isAlive, !reduceMotion else {
            withAnimation(.linear(duration: 0.1)) { breathing = false }
            return
        }
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

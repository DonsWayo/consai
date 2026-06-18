import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// A compose stack as a "plant": a leaf-marked header whose services hang off a branch.
struct StackSection: View {
    @Environment(AppState.self) private var appState
    let stack: Stack
    @State private var expanded = true
    @State private var hovering = false
    @State private var confirmingDown = false

    private var busy: Bool { appState.inFlight.contains(stack.projectName) }
    private var allRunning: Bool { stack.total > 0 && stack.runningCount == stack.total }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded && !stack.services.isEmpty { branch }
        }
        .padding(.horizontal, 12)
        .confirmationDialog(
            "Stop stack \"\(stack.projectName)\"?",
            isPresented: $confirmingDown,
            titleVisibility: .visible,
            actions: {
                Button("Stop \(stack.total) service\(stack.total == 1 ? "" : "s")", role: .destructive) {
                    Task { await appState.composeDown(stack) }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: { Text("All running services in this stack will be stopped.") }
        )
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button { withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() } } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.dim2)
                    .frame(width: 10)
            }.buttonStyle(.plain)

            LeafShape(color: stack.origin == .inferred ? Theme.dim2 : leafColor)

            Text(stack.projectName).font(Theme.ui(14, .semibold)).foregroundStyle(Theme.text)

            if stack.origin == .inferred {
                Text("wild").font(Theme.mono(9)).foregroundStyle(Theme.dim2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.hairline, in: Capsule())
                    .help("Not planted by Consai — link a compose file to tend it")
            }

            Spacer(minLength: 8)

            if busy {
                ProgressView().controlSize(.small)
            } else if hovering {
                actions
            } else {
                Text("\(stack.runningCount) of \(max(stack.total, stack.runningCount))\(memSuffix)")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var leafColor: Color { allRunning ? Theme.jade : (stack.runningCount > 0 ? Theme.amber : Theme.stopDot) }

    private var memSuffix: String {
        let total = stack.services.compactMap(\.memoryBytes).reduce(0, +)
        return total > 0 ? " · \(formatBytes(total))" : ""
    }

    private var branch: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(width: 1.5).padding(.vertical, 3)
            VStack(spacing: 0) {
                ForEach(stack.services) { service in
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.hairline).frame(width: 14, height: 1.5)
                        ContainerRow(container: service)
                    }
                }
            }
            .padding(.leading, 2)
        }
        .padding(.leading, 10)
    }

    @ViewBuilder
    private var actions: some View {
        if appState.composeAvailable, let path = stack.composeFilePath {
            let file = URL(fileURLWithPath: path)
            stackButton("play.fill", "Up") { Task { await appState.composeUp(file: file) } }
            stackButton("stop.fill", "Down") { confirmingDown = true }
            stackButton("folder", "Reveal compose file") {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        } else if appState.composeAvailable {
            // No compose file linked yet (inferred, or labeled but launched outside Consai):
            // let the user point at one to enable up/down.
            stackButton("link", "Link compose file…") {
                if let file = ComposeFilePicker.pick() {
                    appState.linkComposeFile(project: stack.projectName, file: file)
                }
            }
        }
    }

    private func stackButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain).foregroundStyle(Theme.dim).help(help)
    }
}

/// Wraps `NSOpenPanel` for choosing a compose file.
enum ComposeFilePicker {
    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a compose file"
        panel.message = "Select a docker-compose.yml (its folder name becomes the project)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

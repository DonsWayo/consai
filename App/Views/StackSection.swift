import SwiftUI
import ConsaiCore
import AppKit

/// A collapsible compose-stack group: header (name, running summary, actions) + service rows.
struct StackSection: View {
    @Environment(AppState.self) private var appState
    let stack: Stack
    @State private var expanded = true

    private var busy: Bool { appState.inFlight.contains(stack.projectName) }
    private var allRunning: Bool { stack.total > 0 && stack.runningCount == stack.total }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                ForEach(stack.services) { container in
                    ContainerRow(container: container)
                        .padding(.leading, 12)
                    Divider()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Circle()
                .fill(allRunning ? .green : (stack.runningCount > 0 ? .orange : .secondary))
                .frame(width: 8, height: 8)

            Text(stack.projectName).font(.subheadline).fontWeight(.medium).lineLimit(1)

            if stack.origin == .inferred {
                Text("inferred")
                    .font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .help("Not launched by Consai — link a compose file to manage it")
            }

            Text("\(stack.runningCount)/\(stack.total)")
                .font(.caption).foregroundStyle(.secondary)

            Spacer()

            if busy {
                ProgressView().controlSize(.small)
            } else {
                actions
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.secondary.opacity(0.06))
    }

    @ViewBuilder
    private var actions: some View {
        if appState.composeAvailable, let path = stack.composeFilePath {
            let file = URL(fileURLWithPath: path)
            iconButton("play.fill", "Up") { Task { await appState.composeUp(file: file) } }
            iconButton("stop.fill", "Down") { Task { await appState.composeDown(stack) } }
            iconButton("folder", "Reveal compose file") {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        } else if stack.origin == .inferred {
            iconButton("link", "Link compose file…") { linkComposeFile() }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless).help(help)
    }

    private func linkComposeFile() {
        guard let file = ComposeFilePicker.pick() else { return }
        appState.linkComposeFile(project: stack.projectName, file: file)
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

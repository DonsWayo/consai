import SwiftUI
import ConsaiCore

/// The menu bar dropdown panel. Header + service banner + container list.
struct PanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !appState.isServiceRunning {
                ServiceBanner()
            }

            if let error = appState.lastError {
                ErrorBanner(message: error) { appState.clearError() }
            }

            content
        }
        .frame(width: 360)
        .frame(maxHeight: 520)
        .onAppear { appState.setPanelVisible(true) }
        .onDisappear { appState.setPanelVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill").foregroundStyle(.tint)
            Text("Consai").font(.headline)
            if appState.isServiceRunning {
                Text("\(appState.runningCount) running")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { openWindow(id: "create") } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("New container…")
            if appState.composeAvailable {
                Button { composeUp() } label: { Image(systemName: "square.stack.3d.up") }
                    .buttonStyle(.borderless)
                    .help("Start a compose stack…")
            }
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        .padding(12)
    }

    private func composeUp() {
        guard let file = ComposeFilePicker.pick() else { return }
        Task { await appState.composeUp(file: file) }
    }

    @ViewBuilder
    private var content: some View {
        if !appState.isServiceRunning {
            EmptyState(symbol: "bolt.slash", title: "Service not running",
                       subtitle: "Start the container service to manage containers.")
        } else if appState.stacks.isEmpty && appState.standalone.isEmpty {
            EmptyState(symbol: "shippingbox", title: "No containers",
                       subtitle: appState.composeAvailable
                        ? "Run a container, or start a compose stack with the ⊟ button."
                        : "Containers you create or run will show up here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.stacks) { stack in
                        StackSection(stack: stack)
                    }
                    if !appState.standalone.isEmpty {
                        if !appState.stacks.isEmpty {
                            sectionLabel("Containers")
                        }
                        ForEach(appState.standalone) { container in
                            ContainerRow(container: container)
                            Divider()
                        }
                    }
                }
            }
            if !appState.composeAvailable {
                composeHint
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }

    private var composeHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text("Install `container-compose` for stack management")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

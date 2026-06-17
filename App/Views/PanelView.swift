import SwiftUI
import ConsaiCore

/// The menu bar dropdown panel. Header + service banner + container list.
struct PanelView: View {
    @Environment(AppState.self) private var appState

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
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            Button { /* Wave 4: Settings */ } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
                .disabled(true)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if !appState.isServiceRunning {
            EmptyState(symbol: "bolt.slash", title: "Service not running",
                       subtitle: "Start the container service to manage containers.")
        } else if appState.containers.isEmpty {
            EmptyState(symbol: "shippingbox", title: "No containers",
                       subtitle: "Containers you create or run will show up here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.containers) { container in
                        ContainerRow(container: container)
                        Divider()
                    }
                }
            }
        }
    }
}

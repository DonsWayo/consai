import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// Per-container detail: image, command, started, env, ports, mounts; open a shell or logs.
struct DetailWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    let containerID: String

    @State private var detail: ContainerDetail?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loading {
                    ProgressView().padding(24)
                } else if let detail {
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
            Task { detail = await appState.detail(containerID); loading = false }
        }
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

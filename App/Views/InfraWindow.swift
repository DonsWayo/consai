import SwiftUI
import ConsaiCore
import AppKit

/// Networks & volumes: list, create by name, delete.
struct InfraWindow: View {
    @Environment(AppState.self) private var appState
    @State private var newNetwork = ""
    @State private var newVolume = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("NETWORKS")
                createBar(placeholder: "network name", text: $newNetwork) {
                    let n = newNetwork.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    newNetwork = ""; Task { await appState.createNetwork(n) }
                }
                ForEach(appState.networks) { net in
                    infraRow(title: net.name, subtitle: net.subnet ?? "") {
                        Task { await appState.deleteNetwork(net.id) }
                    }
                }
                if appState.networks.isEmpty { emptyRow("No networks") }

                sectionHeader("VOLUMES")
                createBar(placeholder: "volume name", text: $newVolume) {
                    let v = newVolume.trimmingCharacters(in: .whitespaces)
                    guard !v.isEmpty else { return }
                    newVolume = ""; Task { await appState.createVolume(v) }
                }
                ForEach(appState.volumes) { vol in
                    infraRow(title: vol.name, subtitle: "\(vol.driver) · \(vol.source)") {
                        Task { await appState.deleteVolume(vol.name) }
                    }
                }
                if appState.volumes.isEmpty { emptyRow("No volumes") }
            }
            .padding(.bottom, 8)
        }
        .frame(minWidth: 520, minHeight: 380)
        .background(Theme.bg)
        .preferredColorScheme(.dark).tint(Theme.jade)
        .navigationTitle("Networks & Volumes")
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            Task { await appState.loadInfra() }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(Theme.sectionLabel).tracking(2).foregroundStyle(Theme.dim2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
    }

    private func createBar(placeholder: String, text: Binding<String>, add: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).onSubmit(add)
            Button("Create", action: add)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func infraRow(title: String, subtitle: String, delete: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.ui(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Theme.mono(10)).foregroundStyle(Theme.dim2).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Button(action: delete) { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Delete")
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(Theme.ui(12)).foregroundStyle(Theme.dim2)
            .padding(.horizontal, 16).padding(.vertical, 6)
    }
}

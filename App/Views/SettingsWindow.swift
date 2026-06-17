import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// Settings: container system service control, compose availability, poll cadence.
struct SettingsWindow: View {
    @Environment(AppState.self) private var appState
    @AppStorage("pollOpen") private var pollOpen = 2.0
    @AppStorage("pollClosed") private var pollClosed = 15.0
    @AppStorage("groupByNamePrefix") private var groupByNamePrefix = false
    @AppStorage("containerBinaryPath") private var containerBinaryPath = ""
    @AppStorage("composeBinaryPath") private var composeBinaryPath = ""
    @State private var working = false

    var body: some View {
        Form {
            Section("Container service") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(appState.isServiceRunning ? .green : .secondary).frame(width: 8, height: 8)
                        Text(statusText)
                    }
                }
                HStack {
                    Button("Start") { run { await appState.startService() } }
                        .disabled(appState.isServiceRunning || working)
                    Button("Stop") { run { await appState.stopService() } }
                        .disabled(!appState.isServiceRunning || working)
                    if working { ProgressView().controlSize(.small) }
                }
            }

            Section("Compose") {
                LabeledContent("container-compose") {
                    Text(appState.composeAvailable ? "Installed" : "Not installed")
                        .foregroundStyle(appState.composeAvailable ? .green : .secondary)
                }
                if !appState.composeAvailable {
                    Text("Install with: brew install container-compose")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            Section("Binaries") {
                // Native Form TextField (title + prompt) — NOT LabeledContent-wrapped, which on
                // macOS double-labels and misaligns. The prompt shows the actual auto-detected
                // path so it's clear what's in use; typing a path overrides it.
                TextField("container", text: $containerBinaryPath, prompt: Text(detectedPath(container: true)))
                TextField("container-compose", text: $composeBinaryPath, prompt: Text(detectedPath(container: false)))
                Text("Leave empty to auto-detect. Override only if a binary isn't in a standard location. Applies on relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Stacks") {
                Toggle("Group external containers by name prefix", isOn: $groupByNamePrefix)
                Text("Off: only stacks you launch through Consai are grouped (reliable). On: containers that share a `name-` prefix are grouped as inferred stacks — can mis-group unrelated containers.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Refresh cadence") {
                LabeledContent("Panel open") {
                    Stepper("\(pollOpen, specifier: "%.0f")s", value: $pollOpen, in: 1...10)
                }
                LabeledContent("Panel closed") {
                    Stepper("\(pollClosed, specifier: "%.0f")s", value: $pollClosed, in: 5...60, step: 5)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .frame(width: 420, height: 360)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    /// The auto-detected path for a binary (placeholder text), or a hint if none is found.
    private func detectedPath(container: Bool) -> String {
        let url = container
            ? CLIServiceHealth.resolveBinary(explicit: nil)
            : CLIComposeEngine.resolveBinary(explicit: nil)
        return url?.path ?? "not found — enter a path"
    }

    private var statusText: String {
        switch appState.serviceStatus {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .unknown: return "Unknown"
        }
    }

    private func run(_ op: @escaping () async -> Void) {
        working = true
        Task { await op(); working = false }
    }
}

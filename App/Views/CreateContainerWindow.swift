import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// Form to create + run a new container (`container run -d …`).
struct CreateContainerWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var image = ""
    @State private var name = ""
    @State private var command = ""
    @State private var env: [EnvRow] = []
    @State private var ports: [PortRow] = []
    @State private var volumes: [VolumeRow] = []
    @State private var submitting = false

    private var canSubmit: Bool { !image.trimmingCharacters(in: .whitespaces).isEmpty && !submitting }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Image") {
                    TextField("e.g. docker.io/library/nginx:latest", text: $image)
                    TextField("Name (optional)", text: $name)
                    TextField("Command (optional)", text: $command)
                }
                editableSection("Environment", rows: $env, add: { EnvRow() }) { $row in
                    TextField("KEY", text: $row.key)
                    TextField("value", text: $row.value)
                }
                editableSection("Ports (host:container)", rows: $ports, add: { PortRow() }) { $row in
                    TextField("host", text: $row.host).frame(width: 80)
                    Text(":")
                    TextField("container", text: $row.container).frame(width: 80)
                }
                editableSection("Volumes (host:container)", rows: $volumes, add: { VolumeRow() }) { $row in
                    TextField("/host/path", text: $row.host)
                    Text(":")
                    TextField("/container/path", text: $row.container)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)

            Divider()
            HStack {
                if submitting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { submit() }.keyboardShortcut(.defaultAction).disabled(!canSubmit)
            }
            .padding(12)
        }
        .frame(width: 520, height: 540)
        .background(Theme.bg)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    @ViewBuilder
    private func editableSection<Row: Identifiable, Fields: View>(
        _ title: String,
        rows: Binding<[Row]>,
        add: @escaping () -> Row,
        @ViewBuilder fields: @escaping (Binding<Row>) -> Fields
    ) -> some View {
        Section {
            ForEach(rows) { rowBinding in
                HStack {
                    fields(rowBinding)
                    Button { rows.wrappedValue.removeAll { $0.id == rowBinding.wrappedValue.id } } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.borderless)
                }
            }
            Button { rows.wrappedValue.append(add()) } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(.borderless)
        } header: { Text(title) }
    }

    private func submit() {
        submitting = true
        let spec = NewContainerSpec(
            image: image.trimmingCharacters(in: .whitespaces),
            name: name.isEmpty ? nil : name,
            env: Dictionary(env.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a }),
            ports: ports.compactMap { row in
                guard let h = Int(row.host), let c = Int(row.container) else { return nil }
                return PortMapping(hostPort: h, containerPort: c)
            },
            volumes: volumes.filter { !$0.host.isEmpty && !$0.container.isEmpty }
                .map { VolumeMount(hostPath: $0.host, containerPath: $0.container) },
            command: command.isEmpty ? nil : command
        )
        Task {
            let ok = await appState.create(spec)
            submitting = false
            if ok { dismiss() }
        }
    }
}

private struct EnvRow: Identifiable { let id = UUID(); var key = ""; var value = "" }
private struct PortRow: Identifiable { let id = UUID(); var host = ""; var container = "" }
private struct VolumeRow: Identifiable { let id = UUID(); var host = ""; var container = "" }

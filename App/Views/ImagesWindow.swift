import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// Browse local images, pull by reference, delete.
struct ImagesWindow: View {
    @Environment(AppState.self) private var appState
    @State private var pullRef = ""
    @State private var pulling = false
    @State private var deleting: String?
    @State private var confirmingDelete: String?

    var body: some View {
        VStack(spacing: 0) {
            pullBar
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            list
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(Theme.bg)
        .preferredColorScheme(.dark).tint(Theme.jade)
        .navigationTitle("Images")
        .confirmationDialog("Delete image?", isPresented: Binding(
            get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }
        ), presenting: confirmingDelete) { ref in
            Button("Delete \(ref)", role: .destructive) { delete(ref) }
            Button("Cancel", role: .cancel) {}
        } message: { ref in
            Text("Removes the local image \(ref). Containers using it keep running.")
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            Task { await appState.loadImages() }
        }
    }

    private var pullBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle").foregroundStyle(Theme.dim)
            TextField("docker.io/library/nginx:latest", text: $pullRef)
                .textFieldStyle(.roundedBorder)
                .onSubmit(pull)
            Button(action: pull) {
                if pulling { ProgressView().controlSize(.small) } else { Text("Pull") }
            }
            .disabled(pullRef.trimmingCharacters(in: .whitespaces).isEmpty || pulling)
            Button { Task { await appState.loadImages() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).foregroundStyle(Theme.dim).help("Refresh")
        }
        .padding(12)
    }

    @ViewBuilder
    private var list: some View {
        if appState.images.isEmpty {
            EmptyState(symbol: "shippingbox", title: "No images",
                       subtitle: "Pull an image by reference above.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.images) { image in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(image.reference).font(Theme.ui(13, .medium)).foregroundStyle(Theme.text)
                                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                                Text(image.shortDigest).font(Theme.mono(10)).foregroundStyle(Theme.dim2)
                            }
                            Spacer(minLength: 8)
                            if deleting == image.reference {
                                ProgressView().controlSize(.small)
                            } else {
                                Button { confirmingDelete = image.reference } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Delete")
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    }
                }
            }
        }
    }

    private func pull() {
        let ref = pullRef.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { return }
        pulling = true
        Task { if await appState.pullImage(ref) { pullRef = "" }; pulling = false }
    }

    private func delete(_ reference: String) {
        deleting = reference
        Task { await appState.deleteImage(reference); deleting = nil }
    }
}

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
            if let ref = appState.pullProgress {
                pullProgressBanner(ref)
            }
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            list
        }
        .frame(minWidth: 520, minHeight: 360)
        .consaiSurface()
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

    private func pullProgressBanner(_ reference: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Pulling \(reference)…").font(Theme.mono(11)).foregroundStyle(Theme.jade)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.hover)
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
                        ImageRow(
                            image: image,
                            isDeleting: deleting == image.reference,
                            onDelete: { confirmingDelete = image.reference }
                        )
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

/// Single image row with hover lift, matching the ContainerRow affordance.
private struct ImageRow: View {
    let image: ContainerImage
    let isDeleting: Bool
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(image.reference)
                    .font(Theme.ui(13, .medium)).foregroundStyle(Theme.text)
                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(image.shortDigest)
                        .font(Theme.mono(10)).foregroundStyle(Theme.dim2)
                    if let size = image.formattedSize {
                        Text("·").font(Theme.mono(10)).foregroundStyle(Theme.dim2)
                        Text(size).font(Theme.mono(10)).foregroundStyle(Theme.dim2)
                    }
                }
            }
            Spacer(minLength: 8)
            if isDeleting {
                ProgressView().controlSize(.small)
            } else {
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Delete")
                    .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.13), value: hovering)
    }
}

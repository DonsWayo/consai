import SwiftUI

/// Shown when the `container` system service is not running.
struct ServiceBanner: View {
    @Environment(AppState.self) private var appState
    @State private var starting = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Container service not running").font(.callout)
            Spacer()
            Button {
                starting = true
                Task { await appState.startService(); starting = false }
            } label: {
                if starting { ProgressView().controlSize(.small) } else { Text("Start") }
            }
            .controlSize(.small)
            .disabled(starting)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}

/// Transient error surface (replaced by a richer toast system in Wave 5).
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            Text(message).font(.caption).lineLimit(2)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.red.opacity(0.1))
    }
}

/// Centered empty/placeholder state.
struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36).padding(.horizontal, 24)
    }
}

import SwiftUI
import ConsaiKit

/// Shown when the `container` system service is not running.
struct ServiceBanner: View {
    @Environment(AppState.self) private var appState
    @State private var starting = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text("Container service asleep").font(Theme.ui(12)).foregroundStyle(Theme.text)
            Spacer()
            Button {
                starting = true
                Task { await appState.startService(); starting = false }
            } label: {
                if starting { ProgressView().controlSize(.small) } else { Text("Wake").font(Theme.ui(12, .medium)) }
            }
            .buttonStyle(.plain).foregroundStyle(Theme.jade).disabled(starting)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Theme.amber.opacity(0.10))
    }
}

/// Transient error surface.
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.danger)
            Text(message).font(Theme.mono(10.5)).foregroundStyle(Theme.text).lineLimit(2)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(Theme.danger.opacity(0.10))
    }
}

/// Centered empty/placeholder state.
struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Theme.dim2)
            Text(title).font(Theme.ui(14, .semibold)).foregroundStyle(Theme.text)
            Text(subtitle).font(Theme.ui(11)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 28)
    }
}

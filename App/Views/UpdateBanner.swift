import SwiftUI
import ConsaiCore
import ConsaiKit

/// A slim, dismissible banner shown in the panel when a newer version of
/// `container` or `container-compose` is available on GitHub.
struct UpdateBanner: View {
    let update: UpdateAvailability
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.amber)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(update.tool) \(update.latest) available")
                    .font(Theme.ui(11, .medium))
                    .foregroundStyle(Theme.text)
                Text("installed: \(update.current)")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.dim2)
            }

            Spacer(minLength: 4)

            Button {
                openURL(update.releaseURL)
            } label: {
                Text("View release")
                    .font(Theme.ui(10, .medium))
                    .foregroundStyle(Theme.amber)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .help("Dismiss until next check")
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(Theme.amber.opacity(0.08))
    }
}

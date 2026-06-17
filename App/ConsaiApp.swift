import SwiftUI
import ConsaiCore

@main
struct ConsaiApp: App {
    var body: some Scene {
        MenuBarExtra("Consai", systemImage: "shippingbox") {
            PanelView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Scaffold panel. The real implementation (live container list, quick actions,
/// service-health banner, stack grouping) arrives in Waves 2–3 — see specs/.
struct PanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shippingbox.fill")
                Text("Consai").font(.headline)
                Spacer()
            }
            Text("Menu-bar-first manager for Apple containers")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("Scaffold ready. Implementation is organized into waves — see specs/.")
                .font(.caption)
        }
        .padding(12)
        .frame(width: 320)
    }
}

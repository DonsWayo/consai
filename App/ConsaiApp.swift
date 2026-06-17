import SwiftUI
import AppKit

/// Entry point. `--render-shots <dir>` renders UI screenshots and exits; otherwise the
/// normal menu bar app runs.
@main
enum ConsaiEntry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-shots") {
            let dir = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "shots")
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                await ShotRenderer.renderAll(to: dir)
                exit(0)
            }
            app.run()
        } else {
            ConsaiApp.main()
        }
    }
}

struct ConsaiApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Consai Settings", id: "settings") {
            SettingsWindow().environment(appState)
        }
        .windowResizability(.contentSize)

        Window("New Container", id: "create") {
            CreateContainerWindow().environment(appState)
        }
        .windowResizability(.contentSize)

        WindowGroup(id: "logs", for: String.self) { $id in
            LogWindow(containerID: id ?? "")
                .environment(appState)
        }
        .defaultSize(width: 720, height: 460)
    }
}

import SwiftUI
import ConsaiKit
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
        } else if let i = args.firstIndex(of: "--render-live") {
            let dir = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "shots")
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                await ShotRenderer.renderLive(to: dir)
                exit(0)
            }
            app.run()
        } else if let i = args.firstIndex(of: "--render-selfsize") {
            let dir = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "shots")
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                await ShotRenderer.renderSelfSize(to: dir)
                exit(0)
            }
            app.run()
        } else if let i = args.firstIndex(of: "--render-icon") {
            let out = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "icon.png")
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                IconRenderer.render(to: out)
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

        Window("Images", id: "images") {
            ImagesWindow().environment(appState)
        }
        .defaultSize(width: 560, height: 420)

        Window("Networks & Volumes", id: "infra") {
            InfraWindow().environment(appState)
        }
        .defaultSize(width: 560, height: 460)

        Window("Consai Settings", id: "settings") {
            SettingsWindow().environment(appState)
                .preferredColorScheme(.dark).tint(Theme.jade)
        }
        .windowResizability(.contentSize)

        Window("New Container", id: "create") {
            CreateContainerWindow().environment(appState)
                .preferredColorScheme(.dark).tint(Theme.jade)
        }
        .windowResizability(.contentSize)

        WindowGroup(id: "logs", for: String.self) { $id in
            LogWindow(containerID: id ?? "")
                .environment(appState)
                .preferredColorScheme(.dark).tint(Theme.jade)
        }
        .defaultSize(width: 720, height: 460)

        WindowGroup(id: "detail", for: String.self) { $id in
            DetailWindow(containerID: id ?? "")
                .environment(appState)
        }
        .defaultSize(width: 480, height: 420)

        Window("Multi-log", id: "multi-logs") {
            MultiLogWindow().environment(appState)
        }
        .defaultSize(width: 900, height: 500)
    }
}

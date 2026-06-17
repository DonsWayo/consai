import SwiftUI

@main
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

import SwiftUI
import AppKit
import ConsaiCore

/// Screenshot harness for the `--render-shots <dir>` entry mode. Hosts the REAL SwiftUI
/// views in real NSWindows backed by the REAL AppState (live daemon data), then captures
/// each window with `screencapture -l<windowNumber>`. This renders natively (Form/ScrollView
/// /SF Symbols all work, unlike ImageRenderer) and produces authentic on-machine shots.
///
/// Requires Screen Recording permission for the process; without it captures come out blank.
@MainActor
enum ShotRenderer {
    static func renderAll(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = AppState()
        await state.refresh()   // populate from the live daemon

        await shoot(PanelView().environment(state), width: 360, height: 540, name: "panel", dir: dir)
        await shoot(SettingsWindow().environment(state), width: 460, height: 400, name: "settings", dir: dir)
        await shoot(CreateContainerWindow().environment(state), width: 540, height: 580, name: "create-container", dir: dir)

        FileHandle.standardError.write(Data("rendered shots to \(dir.path)\n".utf8))
    }

    private static func shoot<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, dir: URL) async {
        let host = NSHostingController(rootView: AnyView(view.frame(width: width, height: height)))
        let window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let SwiftUI lay out + the async refresh paint.
        try? await Task.sleep(for: .milliseconds(800))

        let path = dir.appendingPathComponent("\(name).png").path
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-o", "-l\(window.windowNumber)", path]
        try? proc.run()
        proc.waitUntilExit()

        window.orderOut(nil)
    }
}

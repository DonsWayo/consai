import SwiftUI
import AppKit
import ConsaiCore
import ConsaiKit

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

        // Mock data so the shots show the full design (a stack + standalone + a resting one).
        let regDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("consai-shots-\(UUID().uuidString)", isDirectory: true)
        var registry = ProjectRegistry()
        registry.record(project: "shop", composeFile: URL(fileURLWithPath: "/Users/you/shop/docker-compose.yml"))
        let store = RegistryStore(directory: regDir)
        try? store.save(registry)

        let mb: (Int) -> UInt64 = { UInt64($0) * 1_048_576 }
        let containers = [
            Container(id: "shop-web", name: "shop-web", image: "docker.io/library/nginx:latest", status: .running, ipAddress: "10.0.1.4", memoryBytes: mb(38), cpuPercent: 2),
            Container(id: "shop-api", name: "shop-api", image: "ghcr.io/acme/api:1.4", status: .running, ipAddress: "10.0.1.5", memoryBytes: mb(196), cpuPercent: 5),
            Container(id: "shop-db", name: "shop-db", image: "postgres:17", status: .running, ipAddress: "10.0.1.6", memoryBytes: mb(178), cpuPercent: 1),
            Container(id: "cache", name: "cache", image: "docker.io/library/redis:7", status: .running, ipAddress: "192.168.64.2", memoryBytes: mb(24), cpuPercent: 3),
            Container(id: "scratch", name: "scratch", image: "docker.io/library/alpine:latest", status: .stopped),
        ]
        let state = AppState(
            containerEngine: MockContainerEngine(containers: containers),
            composeEngine: MockComposeEngine(isAvailable: true),
            serviceHealth: MockServiceHealth(value: .running),
            creator: MockCreator(),
            store: store
        )
        await state.refresh()

        await shoot(PanelView().environment(state), width: 360, height: 540, name: "panel", dir: dir)
        await shoot(SettingsWindow().environment(state), width: 460, height: 400, name: "settings", dir: dir)
        await shoot(CreateContainerWindow().environment(state), width: 540, height: 580, name: "create-container", dir: dir)

        FileHandle.standardError.write(Data("rendered shots to \(dir.path)\n".utf8))
    }

    /// Capture the panel backed by the REAL AppState (live daemon), for QA/authentic shots.
    /// Refreshes twice with a gap so CPU% (needs two samples) populates.
    static func renderLive(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = AppState()
        await state.refresh()
        try? await Task.sleep(for: .seconds(2.5))
        await state.refresh()
        await shoot(PanelView().environment(state), width: 360, height: 600, name: "live-panel", dir: dir)
        await state.loadImages()
        await shoot(ImagesWindow().environment(state), width: 560, height: 420, name: "live-images", dir: dir)
        await state.loadInfra()
        await shoot(InfraWindow().environment(state), width: 560, height: 460, name: "live-infra", dir: dir)
        FileHandle.standardError.write(Data("rendered live panel to \(dir.path)\n".utf8))
    }

    /// Capture the panel at its NATURAL (self-sized) height — the way MenuBarExtra(.window)
    /// sizes its popover. The fixed-size `shoot` can't reveal sizing regressions (it forces a
    /// frame); this one lets the panel report its own ideal height so the menu-bar collapse
    /// bug (ScrollView → 0pt) is reproducible/verifiable off the menu bar.
    static func renderSelfSize(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = AppState()
        await state.refresh()
        try? await Task.sleep(for: .seconds(2.5))
        await state.refresh()

        let view = PanelView().environment(state).preferredColorScheme(.dark).tint(Theme.jade)
        let host = NSHostingController(rootView: AnyView(view))
        let window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: Theme.panelWidth, height: 200),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let the async refresh + preference-driven sizing settle, then snap the window to the
        // panel's fitting height and capture.
        try? await Task.sleep(for: .milliseconds(1200))
        let fit = host.view.fittingSize
        window.setContentSize(NSSize(width: Theme.panelWidth, height: fit.height))
        try? await Task.sleep(for: .milliseconds(400))

        let path = dir.appendingPathComponent("selfsize-panel.png").path
        FileHandle.standardError.write(Data("self-sized panel height = \(Int(fit.height))pt\n".utf8))
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-o", "-l\(window.windowNumber)", path]
        try? proc.run()
        proc.waitUntilExit()
        window.orderOut(nil)
    }

    private static func shoot<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, dir: URL) async {
        let themed = view.frame(width: width, height: height)
            .preferredColorScheme(.dark).tint(Theme.jade)
        let host = NSHostingController(rootView: AnyView(themed))
        let window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)   // force dark for Form/system chrome
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

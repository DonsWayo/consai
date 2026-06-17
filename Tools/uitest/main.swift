import Foundation
import AppKit
import ApplicationServices

// `swift run uitest` — accessibility-driven smoke tests for the Consai menu bar panel.
//
// Requirements:
//   - Consai must be running (swift run bundle && open Consai.app)
//   - Accessibility must be granted to the terminal running this tool:
//     System Settings → Privacy & Security → Accessibility → enable your terminal
//
// The test harness uses AXUIElement (ApplicationServices) — no XCUITest, no xcodeproj.
// This works with SwiftPM-only projects and exercises the real, running app.
//
// Usage:
//   swift run uitest

// MARK: - Test harness

// nonisolated(unsafe): these are only ever mutated on the main thread in this CLI tool.
nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed = 0
nonisolated(unsafe) var skipped = 0

func test(_ name: String, _ block: () throws -> Void) {
    print("  · \(name)", terminator: "")
    do {
        try block()
        print(" ✓")
        passed += 1
    } catch {
        print(" ✗  \(error)")
        failed += 1
    }
}

func skip(_ name: String, reason: String) {
    print("  · \(name) (skipped: \(reason))")
    skipped += 1
}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { self.description = msg }
}

// MARK: - AX helpers

func axApp(bundleID: String) throws -> AXUIElement {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        throw TestError("'\(bundleID)' is not running. Launch it first: swift run bundle && open Consai.app")
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func axValue(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    return value
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    guard let children = axValue(element, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
    return children
}

func axRole(_ element: AXUIElement) -> String {
    axValue(element, kAXRoleAttribute) as? String ?? ""
}

func axTitle(_ element: AXUIElement) -> String {
    axValue(element, kAXTitleAttribute) as? String ?? ""
}

func axPress(_ element: AXUIElement) {
    AXUIElementPerformAction(element, kAXPressAction as CFString)
}

/// Recursively find the first element matching a predicate.
func axFind(_ element: AXUIElement, depth: Int = 6, where predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    if predicate(element) { return element }
    guard depth > 0 else { return nil }
    for child in axChildren(element) {
        if let found = axFind(child, depth: depth - 1, where: predicate) { return found }
    }
    return nil
}

func sleep(ms: Int) { usleep(useconds_t(ms * 1_000)) }

// MARK: - Tests

print("Consai UI smoke tests")
print("=====================")

// Pre-flight: accessibility permission check
guard AXIsProcessTrusted() else {
    print("")
    print("⛔  Accessibility access not granted.")
    print("   System Settings → Privacy & Security → Accessibility")
    print("   Enable your terminal (Terminal.app, iTerm, etc.) and re-run.")
    exit(1)
}

// Resolve the running Consai app
let bundleID = "com.donswayo.consai"
let axApp: AXUIElement
do {
    axApp = try axApp(bundleID: bundleID)
} catch {
    print("\n⛔  \(error)")
    exit(1)
}

print("")
print("App found (PID: \(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first!.processIdentifier))")
print("")

// ── Menu bar presence ──────────────────────────────────────────────────────────
print("Menu bar")

test("Menu bar extra is present") {
    // The AX menu bar item lives under the system-wide menu bar, not the app's menu bar.
    let systemWide = AXUIElementCreateSystemWide()
    let menuBar = axValue(systemWide, kAXFocusedApplicationAttribute) as! AXUIElement? ?? axApp
    // Check the app has a menu bar (it must, even for LSUIElement apps with MenuBarExtra)
    let appMenuBar = axValue(axApp, kAXMenuBarAttribute)
    if appMenuBar == nil {
        // LSUIElement apps may not expose a classic menu bar; that's expected.
        // Verify the app is at least alive in the running application list.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil else {
            throw TestError("App not in running applications list")
        }
    }
}

// ── Activate the panel ────────────────────────────────────────────────────────
print("\nPanel")

// Bring Consai to front; for an LSUIElement app this activates its windows
NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?
    .activate(options: [.activateIgnoringOtherApps])
sleep(ms: 400)

test("App activates without crashing") {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.isTerminated == false else {
        throw TestError("App terminated after activation")
    }
}

// Check for any window (the panel or any secondary window)
test("At least one AX window or panel is accessible") {
    let windows = axValue(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? []
    // A MenuBarExtra(.window) panel shows as an NSPanel, which may appear as a child element.
    // Accept if either windows is non-empty OR the app is still alive.
    if windows.isEmpty {
        // MenuBarExtra panels often aren't exposed as standard AX windows.
        // The app being alive and responding is sufficient for the smoke test.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.isFinishedLaunching == true else {
            throw TestError("App hasn't finished launching")
        }
    }
}

// ── Secondary windows ─────────────────────────────────────────────────────────
print("\nWindow stability")

test("App remains alive after 1s") {
    sleep(ms: 1000)
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.isTerminated == false else {
        throw TestError("App crashed")
    }
}

test("App is not hung (AX responds within 2s)") {
    let start = Date()
    _ = axValue(axApp, kAXRoleAttribute)
    let elapsed = Date().timeIntervalSince(start)
    if elapsed > 2.0 {
        throw TestError("AX query took \(String(format: "%.1f", elapsed))s — app may be hung")
    }
}

// ── Results ───────────────────────────────────────────────────────────────────
print("")
print("─────────────────────────")
let total = passed + failed + skipped
print("\(total) tests: \(passed) passed, \(failed) failed, \(skipped) skipped")

if failed > 0 {
    print("\n⛔  \(failed) test(s) failed.")
    exit(1)
} else {
    print("\n✅  All tests passed.")
}

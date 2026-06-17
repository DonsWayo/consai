import Foundation

// `swift run bundle [debug|release]` — build Consai and assemble a runnable Consai.app.
//
// Native-Swift replacement for the old scripts/bundle.sh. Builds with SwiftPM, lays out the
// .app bundle, copies Info.plist + icon, and ad-hoc signs it for local launch. Real releases
// use Developer ID + notarization (see issue #5).
//
//   swift run bundle            # release (default)
//   swift run bundle debug

let config = CommandLine.arguments.dropFirst().first ?? "release"
guard config == "debug" || config == "release" else {
    fail("Unknown config '\(config)'. Use 'debug' or 'release'.")
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fm = FileManager.default

print("==> Building Consai (\(config), arm64)…")
try run("/usr/bin/env", ["swift", "build", "-c", config, "--arch", "arm64"], cwd: root)

let binary = root.appendingPathComponent(".build/\(config)/Consai")
guard fm.isExecutableFile(atPath: binary.path) else {
    fail("Built binary not found at \(binary.path)")
}

let app = root.appendingPathComponent("Consai.app")
let macOS = app.appendingPathComponent("Contents/MacOS")
let resources = app.appendingPathComponent("Contents/Resources")
print("==> Assembling \(app.lastPathComponent)…")
try? fm.removeItem(at: app)
try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
try fm.createDirectory(at: resources, withIntermediateDirectories: true)

try fm.copyItem(at: binary, to: macOS.appendingPathComponent("Consai"))
try fm.copyItem(at: root.appendingPathComponent("App/Info.plist"),
                to: app.appendingPathComponent("Contents/Info.plist"))

let icon = root.appendingPathComponent("App/Resources/AppIcon.icns")
if fm.fileExists(atPath: icon.path) {
    try fm.copyItem(at: icon, to: resources.appendingPathComponent("AppIcon.icns"))
}

print("==> Ad-hoc signing…")
try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path], cwd: root)

print("==> Built \(app.path)")
print("    Run: open '\(app.path)'")

// MARK: - helpers

func run(_ tool: String, _ args: [String], cwd: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.currentDirectoryURL = cwd
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 { fail("\(args.first ?? tool) failed (\(p.terminationStatus))") }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

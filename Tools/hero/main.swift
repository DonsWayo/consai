import Foundation

// `swift run hero` — render the README hero banner to docs/hero.png.
//
// Builds Consai (debug) and invokes `Consai --render-hero <path>`, which draws the banner with
// SwiftUI's ImageRenderer (no daemon, no Screen Recording permission needed — unlike the
// live screenshot harness).

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fm = FileManager.default

print("==> Building Consai (debug)…")
try run("/usr/bin/env", ["swift", "build"], cwd: root)

let out = root.appendingPathComponent("docs/hero.png")
try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

print("==> Rendering hero…")
try run(root.appendingPathComponent(".build/debug/Consai").path, ["--render-hero", out.path], cwd: root)
print("==> \(out.path)")

// MARK: - helpers

func run(_ tool: String, _ args: [String], cwd: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.currentDirectoryURL = cwd
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        FileHandle.standardError.write(Data("error: \(args.first ?? tool) failed (\(p.terminationStatus))\n".utf8))
        exit(1)
    }
}

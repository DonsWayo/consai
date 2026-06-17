import Foundation

// `swift run icon` — render the app icon and build App/Resources/AppIcon.icns.
//
// Native-Swift replacement for the old scripts/make-icon.sh. Builds Consai, renders the icon
// PNG via `Consai --render-icon`, scales it into an .iconset with `sips`, and packs it with
// `iconutil`.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fm = FileManager.default

print("==> Building Consai (debug)…")
try run("/usr/bin/env", ["swift", "build"], cwd: root)

let tmp = fm.temporaryDirectory.appendingPathComponent("consai-icon-\(ProcessInfo.processInfo.processIdentifier)")
let png = tmp.appendingPathComponent("icon.png")
let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }

print("==> Rendering icon…")
try run(root.appendingPathComponent(".build/debug/Consai").path, ["--render-icon", png.path], cwd: root)

print("==> Scaling icon set…")
for size in [16, 32, 128, 256, 512] {
    try sips(size, size, from: png, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try sips(size * 2, size * 2, from: png, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let out = root.appendingPathComponent("App/Resources/AppIcon.icns")
try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", out.path], cwd: root)
print("==> \(out.path)")

// MARK: - helpers

func sips(_ w: Int, _ h: Int, from: URL, to: URL) throws {
    try run("/usr/bin/sips", ["-z", "\(h)", "\(w)", from.path, "--out", to.path], cwd: root, quiet: true)
}

func run(_ tool: String, _ args: [String], cwd: URL, quiet: Bool = false) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.currentDirectoryURL = cwd
    if quiet {
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
    }
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        FileHandle.standardError.write(Data("error: \(args.first ?? tool) failed (\(p.terminationStatus))\n".utf8))
        exit(1)
    }
}

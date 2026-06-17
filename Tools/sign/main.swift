import Foundation

// `swift run sign` — Developer ID codesign + notarize + staple + DMG.
//
// Requires a one-time build first:   swift run bundle
//
// One-time credential setup (stores securely in the system Keychain — no env vars needed after):
//   xcrun notarytool store-credentials "Consai" \
//     --apple-id you@example.com \
//     --team-id XXXXXXXXXX \
//     --password xxxx-xxxx-xxxx-xxxx   # app-specific password from appleid.apple.com
//
// Required env var:
//   CONSAI_IDENTITY    "Developer ID Application: Your Name (TEAMID)"
//
// Optional env var (default "Consai" — the profile name used in store-credentials above):
//   CONSAI_KEYCHAIN_PROFILE   name of the stored credential profile
//
// Usage:
//   export CONSAI_IDENTITY="Developer ID Application: Juan Carracedo (XXXXXXXXXX)"
//   swift run bundle && swift run sign

func env(_ key: String, default defaultValue: String? = nil) -> String {
    if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
    if let d = defaultValue { return d }
    fail("Missing required env var \(key). See Tools/sign/main.swift for setup.")
}

let identity         = env("CONSAI_IDENTITY")
let keychainProfile  = env("CONSAI_KEYCHAIN_PROFILE", default: "Consai")

let fm   = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let app  = root.appendingPathComponent("Consai.app")

guard fm.fileExists(atPath: app.path) else {
    fail("Consai.app not found. Run `swift run bundle` first.")
}

// 1 — Deep codesign with hardened runtime (required for notarization)
print("==> Signing with Developer ID…")
try run("/usr/bin/codesign", [
    "--force", "--deep", "--options", "runtime",
    "--sign", identity,
    "--timestamp",
    app.path,
], cwd: root)

// Verify the signature before uploading
print("==> Verifying signature…")
try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], cwd: root)

// 2 — Zip for notarytool (DMG is possible but zip is faster; staple will work on the app)
let zipPath = root.appendingPathComponent("Consai-notarize.zip").path
print("==> Zipping for notarization…")
try? fm.removeItem(atPath: zipPath)
try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, zipPath], cwd: root)

// 3 — Submit to Apple notary service using stored keychain credentials (password never in argv)
print("==> Submitting to Apple notary service (this takes 1-5 min)…")
print("    Using keychain profile: \(keychainProfile)")
let submitOutput = try captureOutput("/usr/bin/xcrun", [
    "notarytool", "submit", zipPath,
    "--keychain-profile", keychainProfile,
    "--wait",
    "--output-format", "json",
], cwd: root)

// Parse submission result from JSON
if let data = submitOutput.data(using: .utf8),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    let id = json["id"] as? String ?? "?"
    let status = json["status"] as? String ?? "?"
    if status != "Accepted" {
        fail("Notarization failed (status: \(status), submission id: \(id)).\n"
           + "  Inspect the log: xcrun notarytool log \(id) --keychain-profile \(keychainProfile)")
    }
    print("==> Notarization accepted (id: \(id)).")
} else {
    print("==> notarytool output: \(submitOutput)")
}

// 4 — Staple the notarization ticket to the app
print("==> Stapling…")
try run("/usr/bin/xcrun", ["stapler", "staple", app.path], cwd: root)

// 5 — Build a distributable DMG
let version = appVersion(in: app) ?? "1.0"
let dmgName = "Consai-\(version).dmg"
let dmgPath = root.appendingPathComponent(dmgName).path
let tmpDMG  = root.appendingPathComponent("Consai-tmp.dmg").path

print("==> Creating DMG (\(dmgName))…")
try? fm.removeItem(atPath: tmpDMG)
try? fm.removeItem(atPath: dmgPath)

try run("/usr/bin/hdiutil", [
    "create", tmpDMG,
    "-volname", "Consai",
    "-srcfolder", app.path,
    "-ov", "-format", "UDRW",
], cwd: root)

try run("/usr/bin/hdiutil", [
    "convert", tmpDMG,
    "-format", "UDZO",
    "-imagekey", "zlib-level=9",
    "-o", dmgPath,
], cwd: root)

try? fm.removeItem(atPath: tmpDMG)
try? fm.removeItem(atPath: zipPath)

print("")
print("==> Done.")
print("    Signed + notarized + stapled: \(app.path)")
print("    Distributable DMG:            \(dmgPath)")
print("")
print("Next: create a GitHub release, upload \(dmgName), then:")
print("  swift packaging/update-cask.swift \(dmgName)")

// MARK: - helpers

func appVersion(in appURL: URL) -> String? {
    let plist = appURL.appendingPathComponent("Contents/Info.plist")
    guard let d = try? Data(contentsOf: plist),
          let obj = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any]
    else { return nil }
    return obj["CFBundleShortVersionString"] as? String
}

func run(_ tool: String, _ args: [String], cwd: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.currentDirectoryURL = cwd
    try p.run()
    p.waitUntilExit()
    // Report the tool name + non-secret args only (no credentials in argv here)
    if p.terminationStatus != 0 {
        let displayArgs = args.joined(separator: " ")
        fail("\(tool) \(displayArgs) exited \(p.terminationStatus)")
    }
}

func captureOutput(_ tool: String, _ args: [String], cwd: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.currentDirectoryURL = cwd
    let pipe = Pipe()
    p.standardOutput = pipe
    try p.run()
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if p.terminationStatus != 0 {
        // Do not include args in the error: they contain the keychain profile name but
        // redacting individual flags here is fragile; the profile name is non-sensitive.
        fail("notarytool exited \(p.terminationStatus). Check your keychain profile: \(keychainProfile)")
    }
    return String(decoding: data, as: UTF8.self)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

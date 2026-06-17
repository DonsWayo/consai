import Foundation

// `swift run sign` — Developer ID codesign + notarize + staple + DMG.
//
// Requires a one-time build first:   swift run bundle
//
// Required env vars:
//   CONSAI_IDENTITY    "Developer ID Application: Your Name (TEAMID)"
//   CONSAI_TEAM_ID     Your 10-char Apple team ID
//   CONSAI_APPLE_ID    Your Apple ID email (for notarytool)
//   CONSAI_APP_PWD     App-specific password from appleid.apple.com
//
// Usage:
//   export CONSAI_IDENTITY="Developer ID Application: Juan Carracedo (XXXXXXXXXX)"
//   export CONSAI_TEAM_ID="XXXXXXXXXX"
//   export CONSAI_APPLE_ID="you@example.com"
//   export CONSAI_APP_PWD="xxxx-xxxx-xxxx-xxxx"
//   swift run sign

func env(_ key: String) -> String {
    guard let v = ProcessInfo.processInfo.environment[key], !v.isEmpty else {
        fail("Missing required env var \(key). See Tools/sign/main.swift for setup.")
    }
    return v
}

let identity  = env("CONSAI_IDENTITY")
let teamID    = env("CONSAI_TEAM_ID")
let appleID   = env("CONSAI_APPLE_ID")
let appPwd    = env("CONSAI_APP_PWD")

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

// 3 — Submit to Apple notary service
print("==> Submitting to Apple notary service (this takes 1-5 min)…")
let submitOutput = try output("/usr/bin/xcrun", [
    "notarytool", "submit", zipPath,
    "--apple-id", appleID,
    "--password", appPwd,
    "--team-id", teamID,
    "--wait",
    "--output-format", "json",
], cwd: root)

// Parse submission ID from JSON for error reporting
if let data = submitOutput.data(using: .utf8),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    if let status = json["status"] as? String, status != "Accepted" {
        let id = json["id"] as? String ?? "?"
        fail("Notarization failed (status: \(status), id: \(id)). Run:\n  xcrun notarytool log \(id) --apple-id \(appleID) --password \(appPwd) --team-id \(teamID)")
    }
    print("==> Notarization accepted.")
} else {
    print("==> Notarytool output: \(submitOutput)")
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
print("Next: create a GitHub release, upload \(dmgName), then update the Homebrew cask sha256.")

// MARK: - helpers

func appVersion(in appURL: URL) -> String? {
    let plist = appURL.appendingPathComponent("Contents/Info.plist")
    guard let d = try? Data(contentsOf: plist),
          let obj = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any]
    else { return nil }
    return obj["CFBundleShortVersionString"] as? String
}

@discardableResult
func run(_ tool: String, _ args: [String], cwd: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.currentDirectoryURL = cwd
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 { fail("\(([tool] + args).joined(separator: " ")) exited \(p.terminationStatus)") }
    return ""
}

func output(_ tool: String, _ args: [String], cwd: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.currentDirectoryURL = cwd
    let pipe = Pipe()
    p.standardOutput = pipe
    try p.run()
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if p.terminationStatus != 0 { fail("\(([tool] + args).joined(separator: " ")) exited \(p.terminationStatus)") }
    return String(decoding: data, as: UTF8.self)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

#!/usr/bin/env swift
import Foundation

// Updates the sha256 in consai.rb for a given DMG file.
// Usage: swift packaging/update-cask.swift Consai-0.1.0.dmg

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift packaging/update-cask.swift <Consai-x.y.z.dmg>\n", stderr)
    exit(1)
}

let dmgPath = CommandLine.arguments[1]
guard FileManager.default.fileExists(atPath: dmgPath) else {
    fputs("File not found: \(dmgPath)\n", stderr)
    exit(1)
}

// Compute sha256
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
p.arguments = ["-a", "256", dmgPath]
let pipe = Pipe()
p.standardOutput = pipe
try! p.run()
p.waitUntilExit()
let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
let sha256 = out.split(separator: " ").first.map(String.init) ?? ""
guard sha256.count == 64 else {
    fputs("Could not compute sha256 (got: \(sha256))\n", stderr)
    exit(1)
}

// Extract version from filename: Consai-0.1.0.dmg
let filename = URL(fileURLWithPath: dmgPath).lastPathComponent
let versionRegex = try! NSRegularExpression(pattern: "Consai-([0-9.]+)\\.dmg")
guard let match = versionRegex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
      let range = Range(match.range(at: 1), in: filename) else {
    fputs("Couldn't extract version from filename: \(filename)\n", stderr)
    exit(1)
}
let version = String(filename[range])

// Read, update, write cask
let caskPath = "packaging/consai.rb"
var cask = try! String(contentsOfFile: caskPath)
cask = cask.replacingOccurrences(of: #/version ".*"/#, with: "version \"\(version)\"", options: .regularExpression)
cask = cask.replacingOccurrences(of: #/sha256 ".*"/#, with: "sha256 \"\(sha256)\"", options: .regularExpression)
try! cask.write(toFile: caskPath, atomically: true, encoding: .utf8)

print("Updated packaging/consai.rb")
print("  version: \(version)")
print("  sha256:  \(sha256)")
print("")
print("Next steps:")
print("  1. Commit the updated consai.rb")
print("  2. Push to your homebrew-consai tap: https://github.com/DonsWayo/homebrew-consai")
print("  3. Users install with: brew install --cask donswayo/consai/consai")

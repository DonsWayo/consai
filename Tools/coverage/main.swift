import Foundation

// `swift run coverage` — prints an llvm-cov report for Consai's logic layers.
//
// Run AFTER `swift test --enable-code-coverage` (which writes the profdata + instrumented
// test binary under .build). This tool only shells out to `xcrun llvm-cov`, never to
// `swift`, so it can't deadlock on the SwiftPM build lock the way a command plugin would.
//
// There is no hosted CI for this project (Apple's container SDK graph can't build on hosted
// runners), so coverage is a local step. See docs/TESTING.md.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let build = root.appendingPathComponent(".build")

/// Most-recently-modified file named `name` under `dir` (optionally requiring +x).
func newest(_ name: String, under dir: URL, executable: Bool = false) -> URL? {
    let fm = FileManager.default
    guard let walker = fm.enumerator(
        at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
    ) else { return nil }
    var best: (url: URL, date: Date)?
    for case let url as URL in walker where url.lastPathComponent == name {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard v?.isRegularFile == true else { continue }
        if executable && !fm.isExecutableFile(atPath: url.path) { continue }
        let date = v?.contentModificationDate ?? .distantPast
        if best == nil || date > best!.date { best = (url, date) }
    }
    return best?.url
}

guard let profdata = newest("default.profdata", under: build) else {
    FileHandle.standardError.write(Data(
        "No coverage data found. Run `swift test --enable-code-coverage` first.\n".utf8))
    exit(1)
}
guard let testBin = newest("ConsaiPackageTests", under: build, executable: true) else {
    FileHandle.standardError.write(Data("Could not find the instrumented test binary under .build.\n".utf8))
    exit(1)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
process.arguments = [
    "llvm-cov", "report", testBin.path,
    "-instr-profile", profdata.path,
    root.appendingPathComponent("ConsaiCore/Sources").path,
    root.appendingPathComponent("ConsaiKit/Sources").path,
    "-ignore-filename-regex=(Tests/|MockEngines)",
]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)

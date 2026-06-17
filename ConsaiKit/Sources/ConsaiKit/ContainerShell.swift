import Foundation
import ConsaiCore

/// Opens an interactive shell into a container via Terminal (`container exec -it <id> sh`).
public enum ContainerShell {
    public static func openShell(binaryPath: String, id: String) {
        // Refuse ids that aren't plain container names — they're interpolated into an
        // AppleScript/shell `do script`, so anything exotic is a command-injection risk.
        guard isValidContainerName(id) else { return }
        let command = containerExecCommand(binary: binaryPath, id: id)
        // Escape for AppleScript string literal (defense-in-depth).
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}

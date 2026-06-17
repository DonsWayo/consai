import Foundation

/// Streams a container's logs via `container logs -f <id>` as an `AsyncStream` of lines.
/// The streaming process is separate from the polling engine and is terminated when the
/// stream is cancelled (window closed) or the container's log ends.
public final class LogStreamer: @unchecked Sendable {
    private let binaryURL: URL?
    private var process: Process?
    private var buffer = ""

    public init(binaryPath: String? = nil) {
        self.binaryURL = ContainerBinary.resolve(explicit: binaryPath)
    }

    public func stream(id: String, follow: Bool = true) -> AsyncStream<String> {
        AsyncStream { continuation in
            guard let binaryURL else {
                continuation.yield("`container` CLI not found.")
                continuation.finish()
                return
            }
            let proc = Process()
            proc.executableURL = binaryURL
            proc.arguments = follow ? ["logs", "-f", id] : ["logs", id]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] fh in
                let data = fh.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                // Buffer partial lines so each yielded value is a complete line.
                self?.buffer += chunk
                while let nl = self?.buffer.firstIndex(of: "\n") {
                    let line = String(self!.buffer[..<nl])
                    self?.buffer.removeSubrange(...nl)
                    continuation.yield(line)
                }
            }
            proc.terminationHandler = { _ in
                handle.readabilityHandler = nil
                continuation.finish()
            }

            do {
                try proc.run()
            } catch {
                continuation.yield("Failed to start log stream: \(error)")
                continuation.finish()
                return
            }
            self.process = proc

            continuation.onTermination = { @Sendable _ in
                handle.readabilityHandler = nil
                proc.terminationHandler = nil
                if proc.isRunning { proc.terminate() }
            }
        }
    }

    public func stop() {
        if let process, process.isRunning { process.terminate() }
    }
}

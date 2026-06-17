import Foundation

/// Streams a container's logs via `container logs -f <id>` as an `AsyncStream` of lines.
/// The streaming process is separate from the polling engine and is terminated when the
/// stream is cancelled (window closed) or the container's log ends.
public final class LogStreamer: @unchecked Sendable {
    private let binaryURL: URL?
    private let lock = NSLock()
    private var process: Process?      // guarded by `lock`
    private var buffer = ""            // only touched inside the (serialized) readability handler

    public init(binaryPath: String? = nil) {
        self.binaryURL = ContainerBinary.resolve(explicit: binaryPath)
    }

    private func setProcess(_ proc: Process?) {
        lock.lock(); defer { lock.unlock() }
        process = proc
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
                guard let self else { return }
                let data = fh.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                // Buffer partial lines so each yielded value is a complete line. The handler
                // is invoked serially per file handle, so `buffer` needs no extra locking.
                self.buffer += chunk
                while let newline = self.buffer.firstIndex(of: "\n") {
                    continuation.yield(String(self.buffer[..<newline]))
                    self.buffer.removeSubrange(...newline)
                }
            }
            proc.terminationHandler = { _ in
                handle.readabilityHandler = nil
                continuation.finish()
            }

            // Publish the process BEFORE running so `stop()` can never observe nil after
            // an early termination, and so terminationHandler ordering is well-defined.
            setProcess(proc)
            do {
                try proc.run()
            } catch {
                setProcess(nil)
                continuation.yield("Failed to start log stream: \(error)")
                continuation.finish()
                return
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                handle.readabilityHandler = nil
                proc.terminationHandler = nil
                if proc.isRunning { proc.terminate() }
                self?.setProcess(nil)
            }
        }
    }

    public func stop() {
        lock.lock()
        let proc = process
        lock.unlock()
        if let proc, proc.isRunning { proc.terminate() }
    }
}

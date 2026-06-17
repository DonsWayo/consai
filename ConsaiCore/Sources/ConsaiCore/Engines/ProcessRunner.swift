import Foundation

/// Result of running a subprocess to completion.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs a subprocess to completion. Abstracted so engines can be tested by asserting the
/// invocation (executable/args/cwd) against a spy, without actually spawning anything.
public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], cwd: URL?) async throws -> ProcessResult
}

/// Real implementation backed by `Foundation.Process`, run off the Swift concurrency pool.
public struct SystemProcessRunner: ProcessRunning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 60) { self.timeout = timeout }

    public func run(executable: String, arguments: [String], cwd: URL?) async throws -> ProcessResult {
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let cwd { process.currentDirectoryURL = cwd }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                // `nonisolated(unsafe)`: these are mutated on the concurrent read queues but
                // only read after `group.wait()`, which establishes the happens-before barrier.
                nonisolated(unsafe) let outHandle = outPipe.fileHandleForReading
                nonisolated(unsafe) let errHandle = errPipe.fileHandleForReading
                nonisolated(unsafe) var outData = Data()
                nonisolated(unsafe) var errData = Data()
                nonisolated(unsafe) let proc = process
                nonisolated(unsafe) var didTimeOut = false

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ConsaiError.processFailed(stderr: String(describing: error)))
                    return
                }

                // Drain stdout and stderr CONCURRENTLY — reading one to EOF before the other
                // deadlocks once the unread pipe fills its ~64KB buffer.
                let group = DispatchGroup()
                let readQueue = DispatchQueue(label: "consai.process.read", attributes: .concurrent)
                group.enter()
                readQueue.async { outData = outHandle.readDataToEndOfFile(); group.leave() }
                group.enter()
                readQueue.async { errData = errHandle.readDataToEndOfFile(); group.leave() }

                // Watchdog: terminate a hung child so an action can never block forever.
                let watchdog = DispatchWorkItem {
                    if proc.isRunning { didTimeOut = true; proc.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                process.waitUntilExit()
                watchdog.cancel()
                group.wait()

                if didTimeOut {
                    continuation.resume(throwing: ConsaiError.processFailed(
                        stderr: "Command timed out after \(Int(timeout))s"))
                    return
                }
                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}

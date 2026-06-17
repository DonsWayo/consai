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

                // `nonisolated(unsafe)`: outData/errData are written on the read queues and
                // read only after `group.wait()` (the happens-before barrier); the timeout
                // flags are guarded by `stateLock`.
                nonisolated(unsafe) let outHandle = outPipe.fileHandleForReading
                nonisolated(unsafe) let errHandle = errPipe.fileHandleForReading
                nonisolated(unsafe) var outData = Data()
                nonisolated(unsafe) var errData = Data()
                nonisolated(unsafe) let proc = process
                let stateLock = NSLock()
                nonisolated(unsafe) var didTimeOut = false   // guarded by stateLock
                nonisolated(unsafe) var completed = false    // guarded by stateLock

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
                // It only fires if normal completion hasn't been claimed first — `cancel()`
                // can't stop an already-started block, so the lock decides the winner.
                let watchdog = DispatchWorkItem {
                    stateLock.lock()
                    let shouldTerminate = !completed
                    if shouldTerminate { didTimeOut = true }
                    stateLock.unlock()
                    if shouldTerminate { proc.terminate() }   // terminate outside the lock
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                process.waitUntilExit()
                watchdog.cancel()
                // Claim normal completion unless the watchdog already won; read the flag
                // under the same lock so there's a real happens-before edge.
                stateLock.lock()
                if !didTimeOut { completed = true }
                let timedOut = didTimeOut
                stateLock.unlock()
                group.wait()

                if timedOut {
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

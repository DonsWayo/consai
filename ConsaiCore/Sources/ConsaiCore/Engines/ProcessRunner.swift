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
    public init() {}

    public func run(executable: String, arguments: [String], cwd: URL?) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let cwd { process.currentDirectoryURL = cwd }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ConsaiError.processFailed(stderr: String(describing: error)))
                    return
                }

                // Output here is modest (compose/system commands). Streaming output
                // (e.g. `logs -f`) uses a dedicated streaming process, not this runner.
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}

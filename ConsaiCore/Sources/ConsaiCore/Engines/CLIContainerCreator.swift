import Foundation

/// Resolves the `container` CLI binary from common locations.
enum ContainerBinary {
    static func resolve(explicit: String?) -> URL? {
        var candidates: [String] = []
        if let explicit { candidates.append(explicit) }
        candidates += ["/usr/local/bin/container", "/opt/homebrew/bin/container"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

/// Creates + runs a container via `container run -d …`. (The SDK's `create` requires
/// resolving a `Kernel` + `ImageDescription`; the CLI handles all of that for us.)
public protocol ContainerCreating: Sendable {
    func create(_ spec: NewContainerSpec) async throws
}

public struct CLIContainerCreator: ContainerCreating {
    private let binaryURL: URL?
    private let runner: ProcessRunning

    init(binaryURL: URL?, runner: ProcessRunning) {
        self.binaryURL = binaryURL
        self.runner = runner
    }

    public init(binaryPath: String? = nil, runner: ProcessRunning = SystemProcessRunner()) {
        self.init(binaryURL: ContainerBinary.resolve(explicit: binaryPath), runner: runner)
    }

    public func create(_ spec: NewContainerSpec) async throws {
        guard let binaryURL else { throw ConsaiError.sdk("`container` CLI not found") }
        let result = try await runner.run(
            executable: binaryURL.path, arguments: Self.runArguments(for: spec), cwd: nil
        )
        if result.exitCode != 0 {
            throw ConsaiError.processFailed(stderr: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    /// Build `container run -d …` arguments. Pure + deterministic for testing.
    static func runArguments(for spec: NewContainerSpec) -> [String] {
        var args = ["run", "-d"]
        if let name = spec.name, !name.isEmpty { args += ["--name", name] }
        for key in spec.env.keys.sorted() {
            args += ["--env", "\(key)=\(spec.env[key]!)"]
        }
        for port in spec.ports {
            args += ["--publish", "\(port.hostPort):\(port.containerPort)"]
        }
        for volume in spec.volumes {
            args += ["--volume", "\(volume.hostPath):\(volume.containerPath)"]
        }
        args.append(spec.image)
        if let command = spec.command?.trimmingCharacters(in: .whitespaces), !command.isEmpty {
            args += tokenize(command)
        }
        return args
    }

    /// Shell-style tokenizer honoring single/double quotes and backslash escapes, so
    /// `sh -c "echo hello world"` survives as 3 args, not 4.
    static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false, inDouble = false, hasToken = false
        var escaped = false

        for ch in command {
            if escaped {
                current.append(ch); hasToken = true; escaped = false
            } else if ch == "\\" && !inSingle {
                escaped = true; hasToken = true
            } else if ch == "'" && !inDouble {
                inSingle.toggle(); hasToken = true
            } else if ch == "\"" && !inSingle {
                inDouble.toggle(); hasToken = true
            } else if ch == " " && !inSingle && !inDouble {
                if hasToken { tokens.append(current); current = ""; hasToken = false }
            } else {
                current.append(ch); hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }
}

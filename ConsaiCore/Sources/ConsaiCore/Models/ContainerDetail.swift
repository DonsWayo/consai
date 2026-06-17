import Foundation

public struct PortBinding: Sendable, Hashable, Identifiable {
    public var id: String { "\(host):\(container)/\(proto)" }
    public let host: Int
    public let container: Int
    public let proto: String
    public init(host: Int, container: Int, proto: String) {
        self.host = host; self.container = container; self.proto = proto
    }
}

public struct MountBinding: Sendable, Hashable, Identifiable {
    public var id: String { "\(source)->\(destination)" }
    public let source: String
    public let destination: String
    public init(source: String, destination: String) {
        self.source = source; self.destination = destination
    }
}

/// Full inspect data for one container (from `ContainerClient.get`).
public struct ContainerDetail: Sendable {
    public let id: String
    public let image: String
    public let command: String
    public let env: [String]            // "KEY=VALUE"
    public let ports: [PortBinding]
    public let mounts: [MountBinding]
    public let startedAt: Date?

    public init(id: String, image: String, command: String, env: [String],
                ports: [PortBinding], mounts: [MountBinding], startedAt: Date?) {
        self.id = id; self.image = image; self.command = command
        self.env = env; self.ports = ports; self.mounts = mounts; self.startedAt = startedAt
    }
}

/// The command to open an interactive shell in a container. Pure for testing.
public func containerExecCommand(binary: String, id: String, shell: String = "sh") -> String {
    "\(binary) exec -it \(id) \(shell)"
}

/// Whether a container name/id is safe to interpolate into a shell/AppleScript command.
/// Apple container names are LDH-style (alphanumeric + `-`/`.`/`_`); anything else (spaces,
/// quotes, `;`, `$`, backticks, newlines, …) is rejected to prevent command injection.
public func isValidContainerName(_ name: String) -> Bool {
    !name.isEmpty
        && name.count <= 128
        && name.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil
}

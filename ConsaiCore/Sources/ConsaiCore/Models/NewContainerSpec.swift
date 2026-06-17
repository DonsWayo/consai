import Foundation

public struct PortMapping: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var hostPort: Int
    public var containerPort: Int
    public init(hostPort: Int, containerPort: Int) {
        self.hostPort = hostPort
        self.containerPort = containerPort
    }
}

public struct VolumeMount: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var hostPath: String
    public var containerPath: String
    public init(hostPath: String, containerPath: String) {
        self.hostPath = hostPath
        self.containerPath = containerPath
    }
}

/// A request to create + run a new container. Maps to `container run -d …`.
public struct NewContainerSpec: Sendable {
    public var image: String
    public var name: String?
    public var env: [String: String]
    public var ports: [PortMapping]
    public var volumes: [VolumeMount]
    public var command: String?

    public init(
        image: String,
        name: String? = nil,
        env: [String: String] = [:],
        ports: [PortMapping] = [],
        volumes: [VolumeMount] = [],
        command: String? = nil
    ) {
        self.image = image
        self.name = name
        self.env = env
        self.ports = ports
        self.volumes = volumes
        self.command = command
    }
}

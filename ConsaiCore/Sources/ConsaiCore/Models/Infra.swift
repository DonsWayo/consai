import Foundation

/// A container network.
public struct ContainerNetwork: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let subnet: String?

    public init(name: String, subnet: String? = nil) {
        self.name = name
        self.subnet = subnet
    }
}

/// A named volume.
public struct ContainerVolume: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let driver: String
    public let source: String

    public init(name: String, driver: String, source: String) {
        self.name = name
        self.driver = driver
        self.source = source
    }
}

import Foundation
import ContainerAPIClient
import ContainerResource

/// `ContainerEngine` backed by Apple's `container` SDK over XPC. All SDK types are
/// confined to this file — callers see only Consai's `Container`/`ContainerStatus`.
///
/// Mirrors the proven call patterns from Orchard's `ContainerService`:
/// - list:   `ContainerClient().list()` → `[ContainerSnapshot]`
/// - start:  `bootstrap(id:stdio:)` then `process.start()` (the SDK has no `start(id:)`)
/// - stop:   `stop(id:)`
/// - kill:   `kill(id:, signal: 9)`  (signal is an Int)
/// - delete: `delete(id:, force:)`
public struct SDKContainerEngine: ContainerEngine {
    public init() {}

    public func list() async throws -> [Container] {
        do {
            let snapshots = try await ContainerClient().list()
            return snapshots.map(Self.map)
        } catch {
            throw ConsaiError.sdk(String(describing: error))
        }
    }

    public func start(id: String) async throws {
        // NOTE: start = bootstrap + start (the SDK has no `start(id:)`). If `bootstrap`
        // succeeds but `start` throws, the container may be left bootstrapped-but-not-running;
        // the next poll reflects its real state and the user can retry/stop. Revisit if the
        // SDK adds an atomic start.
        do {
            let process = try await ContainerClient().bootstrap(id: id, stdio: [nil, nil, nil])
            try await process.start()
        } catch {
            throw ConsaiError.sdk(String(describing: error))
        }
    }

    public func stop(id: String) async throws {
        do {
            try await ContainerClient().stop(id: id)
        } catch {
            throw ConsaiError.sdk(String(describing: error))
        }
    }

    public func restart(id: String) async throws {
        try await stop(id: id)
        try await start(id: id)
    }

    public func delete(id: String) async throws {
        do {
            try await ContainerClient().delete(id: id, force: true)
        } catch {
            throw ConsaiError.sdk(String(describing: error))
        }
    }

    public func memoryUsage(id: String) async -> UInt64? {
        try? await ContainerClient().stats(id: id).memoryUsageBytes
    }

    public func cpuUsage(id: String) async -> UInt64? {
        try? await ContainerClient().stats(id: id).cpuUsageUsec
    }

    public func detail(id: String) async throws -> ContainerDetail {
        do {
            let snapshot = try await ContainerClient().get(id: id)
            let config = snapshot.configuration
            let command = ([config.initProcess.executable] + config.initProcess.arguments)
                .filter { !$0.isEmpty }.joined(separator: " ")
            return ContainerDetail(
                id: snapshot.id,
                image: config.image.reference,
                command: command,
                env: config.initProcess.environment.sorted(),
                ports: config.publishedPorts.map {
                    PortBinding(host: Int($0.hostPort), container: Int($0.containerPort), proto: $0.proto.rawValue)
                },
                mounts: config.mounts.map { MountBinding(source: $0.source, destination: $0.destination) },
                startedAt: snapshot.startedDate
            )
        } catch {
            throw ConsaiError.sdk(String(describing: error))
        }
    }

    // MARK: - Mapping (SDK → Consai)

    /// In this SDK the container id *is* its display name (`configuration.id`).
    static func map(_ snapshot: ContainerSnapshot) -> Container {
        // `ipv4Address` is a CIDRv4 ("192.168.64.2/24"); show just the address.
        let ip = snapshot.networks.first.map {
            String(describing: $0.ipv4Address).components(separatedBy: "/").first ?? ""
        }
        return Container(
            id: snapshot.id,
            name: snapshot.id,
            image: snapshot.configuration.image.reference,
            status: mapStatus(snapshot.status.rawValue),
            ipAddress: (ip?.isEmpty == false) ? ip : nil,
            labels: snapshot.configuration.labels
        )
    }

    static func mapStatus(_ raw: String) -> ContainerStatus {
        switch raw {
        case "running": return .running
        case "stopped": return .stopped
        case "stopping": return .stopping
        default: return .unknown
        }
    }
}

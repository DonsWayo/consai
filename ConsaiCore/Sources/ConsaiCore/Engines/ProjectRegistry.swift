import Foundation

/// Pure stack-assembly logic — no I/O. Folds a flat container list into stacks using the
/// `<project>-<service>` naming convention that `container-compose` produces.
///
/// Known projects (launched by Consai) are authoritative. Containers matching a known
/// project's prefix are grouped under it as `.launchedByConsai`. Everything else is
/// standalone for now; **inferred-stack detection from unknown prefixes is completed in
/// Wave 1** (see specs/wave-1-core-engine.md) along with JSON persistence.
public struct ProjectRegistry: Sendable {
    /// projectName -> compose file URL, for stacks Consai launched.
    public private(set) var knownProjects: [String: URL]

    public init(knownProjects: [String: URL] = [:]) {
        self.knownProjects = knownProjects
    }

    public mutating func record(project: String, composeFile: URL) {
        knownProjects[project] = composeFile
    }

    public mutating func remove(project: String) {
        knownProjects[project] = nil
    }

    /// Fold containers into stacks + standalone leftovers.
    public func assemble(containers: [Container]) -> (stacks: [Stack], standalone: [Container]) {
        var grouped: [String: [Container]] = [:]
        var standalone: [Container] = []

        for container in containers {
            if let project = matchingProject(for: container.name) {
                grouped[project, default: []].append(container)
            } else {
                standalone.append(container)
            }
        }

        let stacks = grouped.map { name, services in
            Stack(
                projectName: name,
                composeFilePath: knownProjects[name]?.path,
                services: services,
                origin: knownProjects[name] != nil ? .launchedByConsai : .inferred
            )
        }
        return (stacks, standalone)
    }

    /// Known projects take priority (authoritative). A container `myapp-web` matches
    /// project `myapp`.
    private func matchingProject(for containerName: String) -> String? {
        for project in knownProjects.keys where containerName.hasPrefix("\(project)-") {
            return project
        }
        return nil
    }
}

import Foundation

/// Pure stack-assembly logic — no I/O. Folds a flat container list into stacks using the
/// `<project>-<service>` naming convention that `container-compose` produces.
///
/// Grouping rules:
/// - **Known projects** (launched by Consai, recorded with a compose file) are
///   authoritative. Containers whose name has the `"<project>-"` prefix group under that
///   project as `.launchedByConsai`. A known project with no live containers still appears
///   as an empty stack (so a stopped stack can be re-`up`ed).
/// - **Inferred stacks**: remaining containers are grouped by the substring before their
///   last `"-"`. A candidate shared by **two or more** containers becomes an `.inferred`
///   stack (best-effort — Consai didn't launch it and may lack its compose file).
/// - Everything else is **standalone**.
public struct ProjectRegistry: Codable, Sendable, Equatable {
    /// projectName -> compose file URL, for stacks Consai launched.
    public private(set) var knownProjects: [String: URL]
    /// Most-recently-used compose files (most recent first), for the "recent" picker.
    public private(set) var recentComposeFiles: [URL]

    public init(knownProjects: [String: URL] = [:], recentComposeFiles: [URL] = []) {
        self.knownProjects = knownProjects
        self.recentComposeFiles = recentComposeFiles
    }

    // MARK: - Mutation

    public mutating func record(project: String, composeFile: URL) {
        knownProjects[project] = composeFile
        noteRecent(composeFile)
    }

    public mutating func remove(project: String) {
        knownProjects[project] = nil
    }

    public mutating func noteRecent(_ composeFile: URL, limit: Int = 10) {
        recentComposeFiles.removeAll { $0 == composeFile }
        recentComposeFiles.insert(composeFile, at: 0)
        if recentComposeFiles.count > limit {
            recentComposeFiles = Array(recentComposeFiles.prefix(limit))
        }
    }

    // MARK: - Assembly

    /// Fold containers into stacks + standalone leftovers.
    public func assemble(containers: [Container]) -> (stacks: [Stack], standalone: [Container]) {
        var remaining = containers
        var stacks: [Stack] = []

        // 1. Known projects (authoritative), longest project name first so a more specific
        //    project wins over a shorter one that is a prefix of it.
        for project in knownProjects.keys.sorted(by: { $0.count > $1.count }) {
            let matches = remaining.filter { $0.name.hasPrefix("\(project)-") }
            remaining.removeAll { matched in matches.contains { $0.id == matched.id } }
            stacks.append(
                Stack(
                    projectName: project,
                    composeFilePath: knownProjects[project]?.path,
                    services: matches,
                    origin: .launchedByConsai
                )
            )
        }

        // 2. Inferred stacks: group leftovers by candidate prefix (before the last "-").
        var byCandidate: [String: [Container]] = [:]
        var standalone: [Container] = []
        for container in remaining {
            if let candidate = Self.inferredProject(from: container.name) {
                byCandidate[candidate, default: []].append(container)
            } else {
                standalone.append(container)
            }
        }
        for (candidate, members) in byCandidate {
            if members.count >= 2 {
                stacks.append(
                    Stack(
                        projectName: candidate,
                        composeFilePath: nil,
                        services: members,
                        origin: .inferred
                    )
                )
            } else {
                standalone.append(contentsOf: members)
            }
        }

        // Stable ordering: stacks by name, standalone by name.
        stacks.sort { $0.projectName < $1.projectName }
        standalone.sort { $0.name < $1.name }
        return (stacks, standalone)
    }

    /// The inferred project candidate for a container name: everything before the last
    /// `"-"`. Returns nil when the name has no `"-"` (cannot be part of a stack).
    ///
    /// Heuristic, used only for stacks Consai didn't launch (origin `.inferred`, marked in
    /// the UI): without the compose file we can't know the real project/service boundary, so
    /// a service name containing a `-` (e.g. `app-my-svc`) may group imperfectly. Known
    /// stacks (launched via Consai, matched by exact recorded prefix) are always exact.
    static func inferredProject(from name: String) -> String? {
        guard let idx = name.lastIndex(of: "-"), idx != name.startIndex else { return nil }
        return String(name[name.startIndex..<idx])
    }
}

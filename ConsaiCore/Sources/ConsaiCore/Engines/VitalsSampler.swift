import Foundation

/// Turns successive cumulative `cpuUsageUsec` readings into a CPU percentage. Pure, stateful
/// value type (no I/O) so the sampling logic lives in the domain layer and is unit-testable,
/// instead of as ad-hoc state inside the view model.
public struct VitalsSampler: Sendable {
    private struct Sample { let usec: UInt64; let at: Date }
    private var samples: [String: Sample] = [:]

    public init() {}

    /// Record a cumulative cpu-usec reading at `now`; returns CPU% versus the previous
    /// reading for `id`, or nil on the first reading (no window yet).
    public mutating func recordCPU(id: String, cumulativeUsec: UInt64, at now: Date) -> Double? {
        defer { samples[id] = Sample(usec: cumulativeUsec, at: now) }
        guard let previous = samples[id] else { return nil }
        return cpuPercent(
            previousUsec: previous.usec,
            currentUsec: cumulativeUsec,
            elapsedSeconds: now.timeIntervalSince(previous.at)
        )
    }

    /// Drop samples for ids no longer present (e.g. stopped/removed containers).
    public mutating func retain(ids: Set<String>) {
        samples = samples.filter { ids.contains($0.key) }
    }
}

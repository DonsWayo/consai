import Testing
import Foundation
@testable import ConsaiCore

@Suite struct VitalsTests {

    @Test func cpuPercentComputesFromDelta() {
        #expect(cpuPercent(previousUsec: 0, currentUsec: 1_000_000, elapsedSeconds: 1) == 100)
        #expect(cpuPercent(previousUsec: 0, currentUsec: 500_000, elapsedSeconds: 1) == 50)
        #expect(cpuPercent(previousUsec: 0, currentUsec: 2_000_000, elapsedSeconds: 1) == 200) // multi-core
    }

    @Test func cpuPercentGuardsInvalidInputs() {
        #expect(cpuPercent(previousUsec: 0, currentUsec: 100, elapsedSeconds: 0) == nil)   // no window
        #expect(cpuPercent(previousUsec: 100, currentUsec: 0, elapsedSeconds: 1) == nil)   // counter reset
    }

    @Test func samplerFirstReadingIsNilThenComputes() {
        var sampler = VitalsSampler()
        #expect(sampler.recordCPU(id: "a", cumulativeUsec: 1_000_000, at: Date(timeIntervalSince1970: 0)) == nil)
        #expect(sampler.recordCPU(id: "a", cumulativeUsec: 1_500_000, at: Date(timeIntervalSince1970: 1)) == 50)
    }

    @Test func samplerRetainDropsOthers() {
        var sampler = VitalsSampler()
        let t0 = Date(timeIntervalSince1970: 0)
        _ = sampler.recordCPU(id: "a", cumulativeUsec: 0, at: t0)
        _ = sampler.recordCPU(id: "b", cumulativeUsec: 0, at: t0)
        sampler.retain(ids: ["a"])
        let t1 = Date(timeIntervalSince1970: 1)
        #expect(sampler.recordCPU(id: "b", cumulativeUsec: 1_000_000, at: t1) == nil)   // dropped → first again
        #expect(sampler.recordCPU(id: "a", cumulativeUsec: 1_000_000, at: t1) == 100)   // retained → computes
    }
}

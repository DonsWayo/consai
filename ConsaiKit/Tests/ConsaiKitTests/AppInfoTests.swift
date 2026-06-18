import Testing
@testable import ConsaiKit

@Suite("AppInfo")
struct AppInfoTests {
    /// Build a fixed lookup so the test doesn't depend on a real app bundle.
    private func info(_ keys: [String: Any]) -> AppInfo {
        AppInfo(info: { keys[$0] })
    }

    @Test func displayVersionIncludesBuild() {
        let a = info(["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"])
        #expect(a.version == "1.2.3")
        #expect(a.build == "45")
        #expect(a.displayVersion == "1.2.3 (45)")
    }

    @Test func displayVersionOmitsEmptyBuild() {
        let a = info(["CFBundleShortVersionString": "0.1.0"])
        #expect(a.build == "")
        #expect(a.displayVersion == "0.1.0")
    }

    @Test func displayVersionOmitsRedundantBuild() {
        let a = info(["CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "2.0.0"])
        #expect(a.displayVersion == "2.0.0")
    }

    @Test func fallsBackWhenInfoMissing() {
        let a = info([:])
        #expect(a.version == "dev")
        #expect(a.build == "")
        #expect(a.displayVersion == "dev")
    }
}

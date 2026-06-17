# Testing & coverage

Consai separates code into a **pure, unit-testable logic tier** and a thin **I/O-boundary
tier** that can only be exercised against a live `container` daemon. The two are tested
differently, and coverage should be read per tier — not as a single blended number.

## Running the tests

Everything builds and runs **locally** — there is no GitHub Actions / hosted CI (Apple's
`container` SDK can't build on hosted runners, and the project targets a developer's
macOS 26 / Xcode 26 machine). Run the pre-flight script before pushing:

```bash
scripts/check.sh            # swift build + swift test
scripts/check.sh coverage   # + llvm-cov report for the logic layers
```

Or directly:

```bash
swift test                                  # fast, no daemon required
swift test --enable-code-coverage           # adds llvm-cov instrumentation

PROF=$(find .build -name default.profdata | head -1)
BIN=$(find .build -name ConsaiPackageTests -type f | head -1)
xcrun llvm-cov report "$BIN" -instr-profile "$PROF" ConsaiCore/Sources ConsaiKit/Sources
```

## Tier 1 — pure logic (unit-tested here, ~93% line coverage)

No daemon, no subprocess, no UI. All I/O sits behind protocols, so these are tested with
in-memory fakes and a `SpyProcessRunner` that records argv/cwd instead of spawning.

| Area | File | Line cov |
|------|------|---------:|
| App orchestration | `ConsaiKit/AppState.swift` | ~93% |
| Stack assembly | `ConsaiCore/Engines/ProjectRegistry.swift` | ~94% |
| Registry persistence | `ConsaiCore/Engines/RegistryStore.swift` | ~93% |
| Service health | `ConsaiCore/Engines/CLIServiceHealth.swift` | ~91% |
| Compose CLI wrapper | `ConsaiCore/Engines/CLIComposeEngine.swift` | ~88% |
| Container creation | `ConsaiCore/Engines/CLIContainerCreator.swift` | ~84% |
| Vitals math | `ConsaiCore/Engines/VitalsSampler.swift` | 100% |
| Models | `ConsaiCore/Models/*` | 90–100% |

The remaining few percent are defensive fallbacks and synthesized conformances with no
observable behavior to assert.

## Tier 2 — I/O boundary (integration / E2E, needs a live daemon)

These wrap the `container` XPC API, spawn real subprocesses, or call AppleScript. They are
deliberately thin (map SDK types → Consai models, build argv, drain pipes) and have no logic
to unit-test in isolation — running them at all requires the `container` daemon and real
processes, so they are covered by the `E2ETests` target and manual QA, not by `swift test`.

- `SDKContainerEngine`, `SDKImageEngine`, `SDKInfraEngine` — XPC to the daemon
- `LogStreamer` — long-lived `container logs -f` process
- `ProcessRunner` — the actual `Process` spawn + concurrent pipe drain + timeout
- `ContainerShell` — launches Terminal via AppleScript

Their command-building inputs (argv, parse rules) *are* unit-tested as pure statics
(`pullArguments`, `deleteArguments`, `network*Args`, `parseStatus`, `runArguments`,
`tokenize`, …); only the live wiring is left to E2E.

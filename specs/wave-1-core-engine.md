# Wave 1 — ConsaiCore (engine, no UI)

**Goal:** a UI-free Swift package that fully models containers/stacks and wraps the two
backends behind protocols, with the pure logic unit-tested. This is the piece the future
full app reuses.

## Deliverables

### Models (`Sources/ConsaiCore/Models/`)
- `Container` — id, name, image, status (`ContainerStatus`), ports, createdAt, labels.
  Mapped from the SDK's `ContainerSnapshot` (do **not** leak SDK types out of the engine).
- `ContainerStatus` — `.running | .stopped | .starting | .stopping | .unknown`.
- `Stack` — projectName, composeFilePath?, services `[Container]`, origin
  (`.launchedByConsai | .inferred`), derived `runningCount/total`.
- `ServiceStatus` — `.running | .stopped | .unknown`.
- `ConsaiError` — typed errors (serviceDown, composeMissing, processFailed(stderr),
  sdkError(underlying)).

### Protocols (the seams)
- `ContainerEngine` — `list() async throws -> [Container]`, `start/stop/restart/delete(id:)`,
  `create(_ options:) async throws`, `stats(id:)`.
- `ComposeEngine` — `up(file:) / down(file:) async throws`, `isAvailable -> Bool`.
- `ServiceHealthChecking` — `status() async -> ServiceStatus`, `start() / stop() async throws`.

### Implementations
- `SDKContainerEngine: ContainerEngine` — wraps `apple/container` `ContainerClient` etc.,
  maps `ContainerSnapshot -> Container`. Thin; isolate all SDK imports here.
- `CLIComposeEngine: ComposeEngine` — builds and runs `container-compose up -d` / `down`
  via `Foundation.Process` with the compose file's directory as `cwd`. Probes binary path.
- `CLIServiceHealth: ServiceHealthChecking` — `container system status/start/stop`.
- `ProjectRegistry` — **pure** stack-assembly: `assemble(containers:) -> (stacks:[Stack],
  standalone:[Container])` using `<project>-<service>` prefix + known projects; plus
  persistence (`record/remove/list`) to JSON in Application Support.

## Acceptance / tests (`Tests/ConsaiCoreTests/`)
- `ProjectRegistryTests`: prefix folding; known vs inferred origin; standalone leftovers;
  mis-group edge cases (e.g. `foo-bar` standalone vs `foo` project).
- `CLIComposeEngineTests`: assert the exact `Process` argv + `cwd` for up/down **without
  executing** (inject a process-spawner protocol).
- `ModelMappingTests`: `ContainerSnapshot -> Container` mapping (use fixtures).
- Engines behind protocols so Wave 2's `AppState` can mock them.

## Done when
- `swift test` passes with no I/O in pure tests.
- `SDKContainerEngine` compiles against the `apple/container` SPM dependency.
- No SwiftUI / AppKit imports anywhere in `ConsaiCore`.

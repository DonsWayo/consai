# Wave 2 — Menu bar app shell + panel

**Goal:** a running menu bar app that lists live containers with working quick actions
and a service-health banner. Stacks not yet grouped (Wave 3) — show a flat list.

**Depends on:** Wave 1.

## Deliverables

### App shell (`Sources/Consai/`)
- `ConsaiApp` (`@main`) — `MenuBarExtra("Consai", systemImage:)` with `.menuBarExtraStyle(.window)`
  so the dropdown is a real panel we control.
- `Info.plist`: `LSUIElement = true` (agent app, no Dock icon). Non-sandboxed entitlements
  (empty `.entitlements`, like Orchard).
- `AppState` (`@Observable`/`ObservableObject`) — owns `ContainerEngine` +
  `ServiceHealthChecking`; holds `[Container]` and `ServiceStatus`; drives polling.

### Polling
- Adaptive timer: ~2s while panel open, ~15s while closed (track open state via
  `MenuBarExtra` scene phase / panel callbacks).
- `refresh()` calls `engine.list()`, diffs, publishes. Immediate `refresh()` after any action.
- Optimistic update on actions; revert + toast on throw (toast UI can be minimal here,
  fleshed out in Wave 5).

### Panel UI
- Header: title, running count, refresh, gear (opens Settings — stub until Wave 4), `+` (create — stub until Wave 4).
- Container rows: status dot (color by `ContainerStatus`), name, image; hover/trailing
  quick actions: start / stop / restart / delete (with confirm on delete).
- **Service-health banner**: when `ServiceStatus != .running`, show
  *"Container service not running — [Start]"*; disable container actions; `[Start]` runs
  `ServiceHealthChecking.start()`.
- Menu bar icon reflects state: normal vs amber (service down) + running-count badge.

## Acceptance / tests
- `AppStateTests` with a **mock** `ContainerEngine`: refresh populates list; action calls
  engine then re-refreshes; failed action reverts optimistic state.
- Manual: start/stop a real container from the panel; status dot updates within ~2s;
  stopping the `container` service shows the banner and disables actions.

## Done when
- App launches as a menu bar item (no Dock icon), lists real containers, quick actions work.
- Service-down banner appears/clears correctly.

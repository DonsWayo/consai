# Wave 4 — Pop-out windows

**Goal:** the heavy tasks that don't fit a panel — log streaming, creating a container,
settings — each in a dedicated window. These windows are built to be reusable by the
future full app.

**Depends on:** Wave 1 (engines) + Wave 2 (app shell). Independent of Wave 3.

## Deliverables

### Log window (`LogWindow`)
- Opened from a container row ("Logs"). One window per container (reuse if already open).
- Tails `container logs -f <name>` as its own `Process` (separate from the 2s poll).
- Features: autoscroll toggle, text filter/search highlight, copy, clear; show exit if the
  stream ends. Terminate the `Process` on window close.

### Create-container window (`CreateContainerWindow`)
- Opened from the panel `+`. Simple form → `ContainerEngine.create(_ options:)`:
  - image (with recent-images suggestions if cheap), name, env vars (key/value rows),
    published ports (`host:container`), volume mounts, optional command.
- Validate before submit; on success close + re-poll; on failure show `stderr`/error inline.
- Maps form → SDK `ContainerCreateOptions` (mapping lives in `ConsaiCore` Wave 1, extended
  here as needed).

### Settings window (`SettingsWindow`)
- **Service**: show `container` system service status; Start / Stop buttons
  (`ServiceHealthChecking`).
- **Compose**: `container-compose` binary path (auto-detected, overridable); show
  detected version / "not installed" + brew hint.
- **Polling**: open/closed intervals (defaults 2s / 15s).
- Persist settings (UserDefaults).

### Window plumbing
- Use SwiftUI `Window`/`WindowGroup` scenes alongside `MenuBarExtra`. Since `LSUIElement`
  hides the Dock icon, ensure windows can still be focused/activated
  (`NSApp.activate(ignoringOtherApps:)` as needed).
- All spawned processes tracked centrally and killed on app quit.

## Acceptance / tests
- `CreateContainer` form → `ContainerCreateOptions` mapping unit test.
- Manual: stream logs of a chatty container (filter works, no zombie process after close);
  create a container via the form and see it appear; toggle the service from Settings.

## Done when
- Logs stream and stop cleanly; containers can be created from the UI; settings persist and
  control the service + compose path + poll intervals.

# Consai — Project Instructions

A macOS **menu-bar-first** app for Apple's `container` tooling. Lightweight companion to
full GUIs like Orchard. See [`specs/00-design.md`](specs/00-design.md) for the design and
[`specs/README.md`](specs/README.md) for the implementation waves.

## What this is / is not

- **Is:** a `MenuBarExtra` SwiftUI app + a reusable, UI-free `ConsaiCore` Swift package
  that wraps Apple's `container` SDK and the `container-compose` CLI.
- **Is not:** a compose engine (we integrate the existing
  [`container-compose`](https://github.com/Mcrich23/Container-Compose), we do not rebuild
  it) and not a full windowed GUI (deferred; `ConsaiCore` is designed so one can be added
  later).

## Environment & runtime requirements

- **macOS 26 (Tahoe)** — `container` only supports macOS 26.
- **Xcode 26 / Swift 6.2** — required to build (uses the `apple/container` Swift 6.2 package).
- **`container`** installed (`/usr/local/bin/container`) and its system service running.
- **`container-compose`** installed (`brew install container-compose`) — optional, only for
  stack features. The app degrades gracefully without it.
- **Runtimes via `mise` only** — never `brew install` a *runtime* (node/ruby/python/etc).
  Build tools like `xcodegen` are fine via `mise` (`mise use -g xcodegen`) or brew.
- **Non-sandboxed app** — empty entitlements (like Orchard). Required to reach the XPC
  daemon and spawn `Process`. Distributed outside the App Store.

## Build / run

**The project builds with SwiftPM, not an `.xcodeproj`** (see R11 — Xcode's `.xcodeproj`
SwiftPM integration can't build the SDK's transitive package modules).

```bash
# Build the app
swift build                      # debug; add -c release for release

# Build + assemble a runnable Consai.app (LSUIElement menu bar agent, ad-hoc signed)
scripts/bundle.sh                # release by default; `scripts/bundle.sh debug` for debug
open Consai.app

# Run the unit tests (pure ConsaiCore logic; no `container` needed)
swift test

# GUI development in Xcode: open the package directly (uses the working SwiftPM build)
open Package.swift               # do NOT generate/open an .xcodeproj
```

> First build is slow: SwiftPM compiles the entire `apple/container` SDK graph from source
> (BoringSSL, zstd, NIO, gRPC, ~3 min). It caches afterward — later builds are incremental.

> The `.xcodeproj` is **generated** — do not hand-edit it. Change `project.yml` and re-run
> `xcodegen generate`. Consider not committing the `.xcodeproj` (or committing it but
> treating `project.yml` as source of truth).

## Conventions

- `ConsaiCore` is **UI-free and pure** — no SwiftUI/AppKit imports. All I/O (SDK, CLI,
  filesystem) sits behind protocols (`ContainerEngine`, `ComposeEngine`,
  `ServiceHealthChecking`) so it is mockable and reusable by a future full app.
- Do **not** leak `apple/container` SDK types out of `SDKContainerEngine`; map to Consai's
  own `Models`.
- **Git identity for this repo is personal**: `DonsWayo` / `djwayomix@gmail.com` (set
  locally). **No AI attribution** in commits, code, or docs.
- Tooling preferences: **`gh`** for GitHub, **`acli`** for Jira, **Playwright MCP** for
  browser tasks.

---

## ⚠️ Risk register

Read before building. These are the things most likely to bite.

### R1 — SDK library version MUST match the installed `container` daemon (HIGH)
**Pinned to `1.0.0`** to match the installed `container` daemon. A library/daemon version
skew causes XPC **wire-decoding errors at runtime** (E2E caught `stop` failing with
`signal` String-vs-number when the lib was 0.12.3 against a 1.0.0 daemon). The earlier
0.12.3 pin only existed to dodge an Xcode `.xcodeproj` bug — moot now that we build with
SwiftPM (see R11). If a user's daemon is a different major, the pin must track it.
Mitigation: all SDK use is isolated in `SDKContainerEngine` + mapping (one file to adjust).

### R2 — Stack grouping is by NAME PREFIX, not a label (HIGH)
`container-compose` names containers `<project>-<service>` and does **not** stamp a project
label or isolate networks/volumes per project (confirmed in its source). So grouping is
heuristic: a standalone container named `foo-bar` can be mis-grouped under project `foo`.
**Mitigation:** keep our own `ProjectRegistry` of stacks *we* launched (authoritative);
mark everything else as **inferred** and visually distinct; **never run a destructive
`down` on an inferred stack without a user-linked compose file.**

### R3 — `container-compose` has no importable library product (MEDIUM)
`ContainerComposeCore` exists but the package declares no `.library` product, so we cannot
SPM-import it. We shell out to the CLI. **Mitigation:** keep compose behind the
`ComposeEngine` protocol; if we later upstream a library product, swap the impl with no UI
change. Also: the CLI's flags/output may change — assert argv in tests and parse defensively.

### R4 — No push events; we poll (MEDIUM)
`list()` is request/response. Aggressive polling wastes CPU; lazy polling feels stale.
**Mitigation:** adaptive intervals (2s open / 15s closed) + optimistic updates + immediate
re-poll after actions. Revisit if the SDK gains an event stream.

### R5 — `LSUIElement` window activation (MEDIUM)
A Dock-less agent app can have trouble bringing pop-out windows (logs/create/settings) to
front. **Mitigation:** use `NSApp.activate(ignoringOtherApps:)` and proper window scenes;
manually verify focus behavior on each window.

### R6 — Zombie / leaked processes (MEDIUM)
`container logs -f` and `container-compose` are long-lived `Process`es. If not tracked they
leak on window close / quit. **Mitigation:** central process registry; terminate on
window-close and `applicationWillTerminate`.

### R7 — Build environment not present here (MEDIUM)
On this machine `xcodebuild`/Xcode 26 was not detected and `container-compose` is not
installed, so the app **cannot be compile-verified locally yet**. `container` *is* present.
**Mitigation:** treat "builds in Xcode 26" as a manual gate the developer runs. There is no
hosted CI (Apple's SDK graph can't build on hosted runners) — verify locally with `swift
test` / `swift package check` (the `check` SwiftPM command plugin). See `docs/TESTING.md`.

### R8 — Crowded ecosystem (LOW / product)
Many compose tools and full GUIs already exist; the menu-bar-first niche is the
differentiator. **Mitigation:** stay focused on the menu bar experience; don't drift into
rebuilding compose or a full GUI in v1.

### R9 — Non-sandboxed distribution friction (LOW)
Outside the App Store → must code-sign (Developer ID) + notarize, or Gatekeeper blocks it.
**Mitigation:** Wave 5 covers signing/notarization + a Homebrew cask; document the steps.

### R11 — Build with SwiftPM, NOT an .xcodeproj (MEDIUM, build — resolved)
Xcode 26.5's `.xcodeproj` SwiftPM integration cannot build this SDK's large transitive
package graph: it fails to wire up transitive modules (`ServiceContextModule`, `SwiftASN1`,
`Logging`, `SystemPackage`, …) and, with explicit modules, the C-library builtin `.pcm`s.
Adding packages directly is unreliable whack-a-mole. **Resolution:** the project builds with
**SwiftPM** (`Package.swift`) — the same build system that compiles the graph cleanly — and
`scripts/bundle.sh` wraps the executable into `Consai.app`. Do **not** reintroduce XcodeGen /
`.xcodeproj`; for Xcode GUI work, `open Package.swift`. (`apple/container` is also
Apple-silicon-only — builds are arm64.)

### R10 — Destructive actions (LOW, but high blast radius)
`delete` container and `down` stack remove resources. **Mitigation:** confirm on delete;
gate `down` on a known compose file; never guess.

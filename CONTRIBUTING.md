# Contributing to Consai

Thanks for taking the time to improve Consai. This document covers the
practical steps — for the *why* (risk register, conventions, design
rationale), see [`CLAUDE.md`](CLAUDE.md), which is the source of truth.

## Project shape

- **ConsaiCore** — UI-free Swift package. Container/compose engines behind
  protocols. Reusable by a future full GUI.
- **ConsaiKit** — orchestration layer (`AppState`, mock engines, shell
  launcher). UI-free, unit-testable.
- **Consai** (`App/`) — thin SwiftUI `MenuBarExtra` layer.
- **Tools/** — native-Swift tooling (`bundle`, `icon`, `hero`, `coverage`,
  `sign`, `uitest`). Run via `swift run <name>`.

Read [`CLAUDE.md`](CLAUDE.md) before opening a PR — particularly:

- **R1** — the SDK pin must match your installed `container` daemon. A
  library/daemon skew causes XPC wire-decoding errors at runtime.
- **R11** — builds with SwiftPM (`Package.swift`), NOT an `.xcodeproj`.
  Xcode's `.xcodeproj` SwiftPM integration can't wire up this SDK's
  transitive package graph.
- **R7** — there is no hosted CI (Apple's SDK graph won't build on hosted
  runners). Verify locally with `swift test`.

## Build & test

```bash
swift build                      # build the app
swift test                       # unit tests (no daemon needed)
swift run bundle                 # assemble Consai.app
swift run hero                   # render docs/hero.png
```

First build is slow (~3 min) — SwiftPM compiles the entire
`apple/container` SDK graph from source. It caches afterward.

## Before opening a PR

1. `swift test` passes (the suite runs in a few seconds, no daemon needed).
2. If your change touches SDK code, run the E2E suite on your own machine:
   `CONSAI_E2E=1 swift test`. It needs `container` + `container-compose`
   running and pulls a real `alpine` image.
3. If your change is user-visible, regenerate the screenshots if they
   apply: `swift run bundle && open Consai.app` and capture the panel.
4. **One PR per concern.** Keep diffs focused; the project history is
   deliberately linear and reviewable.

## Style

- **`ConsaiCore` stays UI-free.** No SwiftUI/AppKit imports. All I/O sits
  behind a protocol (`ContainerEngine`, `ComposeEngine`,
  `ServiceHealthChecking`).
- **Don't leak `apple/container` SDK types.** Map to Consai's own `Models`
  at the boundary.
- **No AI attribution in commits, code, or docs.** Git identity for this
  repo is personal (`DonsWayo` / `djwayomix@gmail.com`).
- **Tooling:** `gh` for GitHub, `acli` for Jira, Playwright MCP for
  browser tasks.

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug.yml). Include:

- macOS version (`sw_vers`)
- `container` version (`container --version`)
- `container-compose` version (if installed)
- The exact command you ran and the output you got
- Whether `swift test` passes on your machine

## Suggesting features

Use the [feature request template](.github/ISSUE_TEMPLATE/feature.yml).
Keep in mind [R8](CLAUDE.md): Consai is a **menu-bar-first** companion to
full GUI tools like [Orchard](https://github.com/andrew-waters/orchard).
Big-window feature ideas likely belong in a separate project.

## Security

See [`SECURITY.md`](SECURITY.md). Don't file public issues for
vulnerabilities — use GitHub Security Advisories.
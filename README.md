# Consai 🌳📦

A **menu-bar-first** macOS app for [Apple's `container`](https://github.com/apple/container).
The lightweight companion to full GUIs like [Orchard](https://github.com/andrew-waters/orchard):
glance at your containers — grouped into compose stacks — and act, right from the menu bar.

> **Consai** = **con**tainer + bon**sai** — a small, contained tree.

## Status

Early scaffold. Design is approved; implementation is organized into waves.
See [`specs/`](specs/) (start with [`specs/00-design.md`](specs/00-design.md)).

## Requirements

- macOS 26 (Tahoe), Xcode 26 / Swift 6.2
- [`container`](https://github.com/apple/container) installed + its system service running
- [`container-compose`](https://github.com/Mcrich23/Container-Compose) — optional, for stacks
  (`brew install container-compose`)

## Build

Consai builds with **SwiftPM** (not an `.xcodeproj` — see `CLAUDE.md` R11):

```bash
swift build                  # build the app
scripts/bundle.sh            # build + assemble a runnable Consai.app, then: open Consai.app
swift test                   # ConsaiCore unit tests (no container needed)
open Package.swift           # Xcode GUI development (uses SwiftPM's build)
```

## Architecture

- **`ConsaiCore`** — UI-free Swift package: container/compose engines (behind protocols),
  stack-assembly, service health. Reusable by a future full app.
- **`Consai`** (`App/`) — thin SwiftUI `MenuBarExtra` layer.

See [`CLAUDE.md`](CLAUDE.md) for the risk register and conventions.

## License

MIT (intended).

# Changelog

All notable changes to Consai are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Dates are `YYYY-MM-DD` in the project's local timezone.

## [Unreleased]

### Added
- Homebrew cask (`packaging/consai.rb`) with `license "MIT"` and
  `macos: ">= :tahoe"` (macOS 26) gating.
- Repo hygiene files: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`, `.github/ISSUE_TEMPLATE/{bug,feature}.yml`,
  `.github/PULL_REQUEST_TEMPLATE.md`.
- README hero banner (`docs/hero.png`) and 1280×640 social preview
  (`docs/social-preview.png`).
- `--version` / `-v` CLI flag and an About section in Settings.
- `AppInfo` (in `ConsaiKit`) for testable version/build metadata.

### Removed
- Stray `docs/mockups/preview.png` (Android emulator screenshot from a
  pre-SwiftUI prototype).

## [0.1.0] — 2026-06-19

Initial release. Menu-bar-first macOS companion for Apple's `container`
tooling and `container-compose` stacks.

### Added
- `MenuBarExtra` SwiftUI app — see every container, grouped into the
  compose stack it belongs to, with live CPU/memory/IP.
- One-click actions: start, stop, restart, delete, view logs, open shell.
- Pop-out panel for the full garden (stacks + standalone containers).
- Compose stack grouping — projects launched through Consai are tracked
  reliably; external containers can be grouped by name prefix
  (off by default).
- Adaptive polling — 2s open / 15s closed, plus immediate re-poll after
  every action.
- Graceful degradation when `container-compose` is missing, with a
  first-run setup wizard (`SetupWindow`).
- Live update checker for `container` and `container-compose` releases.
- Native-Swift build tooling: `bundle`, `icon`, `hero`, `coverage`,
  `sign`, `uitest` (all under `Tools/`).
- 108 unit tests across 27 suites covering `ConsaiCore` and
  `ConsaiKit` (no daemon needed).

### Known limitations
- Build requires Xcode 26 / Swift 6.2 — there is no hosted CI (Apple's
  `container` SDK graph won't build on hosted runners). Verify locally.
- Stack grouping is heuristic (name prefix) for non-Consai containers;
  see [R2 in CLAUDE.md](CLAUDE.md) for the rationale.
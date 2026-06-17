# Consai — Specs

Implementation is broken into dependency-ordered **waves**. Each wave is independently
buildable and leaves the project in a working state.

| Wave | Spec | Outcome |
|------|------|---------|
| — | [`00-design.md`](00-design.md) | Master design (approved) — read first |
| 1 | [`wave-1-core-engine.md`](wave-1-core-engine.md) | `ConsaiCore` package: models, engines, registry, health + unit tests. No UI. |
| 2 | [`wave-2-menubar-panel.md`](wave-2-menubar-panel.md) | App shell + `MenuBarExtra` panel: live container list, quick actions, service-health banner. |
| 3 | [`wave-3-compose-stacks.md`](wave-3-compose-stacks.md) | Stack grouping UI, compose up/down, project-registry persistence, recent files. |
| 4 | [`wave-4-windows.md`](wave-4-windows.md) | Log window, create-container window, settings window. |
| 5 | [`wave-5-polish-packaging.md`](wave-5-polish-packaging.md) | Toasts, optimistic-update polish, app icon, signing/notarization, release. |

## Dependency order

```
Wave 1 (core) ──► Wave 2 (panel) ──► Wave 3 (stacks)
                          └────────► Wave 4 (windows)
                                            └──► Wave 5 (polish/packaging)
```

Wave 2 and the engine pieces of Wave 4 both depend only on Wave 1; Wave 3 depends on
Wave 2's panel + Wave 1's `ComposeEngine`.

## Conventions

- Every wave ends green: `swift test` (ConsaiCore) passes, app builds in Xcode 26.
- `ConsaiCore` stays UI-free and pure; all I/O sits behind protocols for mocking.
- See root `CLAUDE.md` for environment requirements and the live **risk register**.

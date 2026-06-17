# Wave 5 — Polish & packaging

**Goal:** make it feel finished and shippable.

**Depends on:** Waves 1–4.

## Deliverables

### UX polish
- Transient **toast** system for action results/errors (replaces minimal Wave 2 stub).
- Optimistic-update polish: subtle in-flight spinners on rows/headers; consistent revert.
- Empty states: "no containers", "service not running", "container-compose not installed".
- Keyboard niceties; sensible panel sizing; light/dark + appropriate menu bar icon variants.

### Packaging / distribution (mirrors Orchard: outside the App Store)
- App icon + assets.
- Code signing (Developer ID) + **notarization** + stapling; document the steps.
- Release artifact: signed `.app` in a `.dmg` or `.zip`.
- **Homebrew cask** (`brew install --cask consai`) — the expected install path for this
  ecosystem.
- `--version`, basic about box, license.

### Quality gates
- CI runs `ConsaiCore` unit tests (pure, no `container` needed).
- Manual release checklist: fresh machine install, service-down path, compose-missing path,
  create/stop/delete, stack up/down.

## Done when
- Signed + notarized build installs cleanly via cask, looks polished, and handles the
  degraded states gracefully.

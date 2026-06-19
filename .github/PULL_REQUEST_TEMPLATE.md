## Summary

<!-- One-paragraph description of the change and why. -->

## Risk register touchpoints

<!-- Tick any CLAUDE.md risk that your change interacts with. -->
- [ ] R1 — SDK pin / daemon version
- [ ] R2 — stack grouping heuristic
- [ ] R3 — `container-compose` CLI surface
- [ ] R4 — polling cadence
- [ ] R5 — `LSUIElement` window activation
- [ ] R6 — process leaks (logs, compose)
- [ ] R7 — local-only verification (no CI)
- [ ] R8 — menu-bar-first scope
- [ ] R9 — code signing / notarization
- [ ] R11 — SwiftPM, not `.xcodeproj`

## Testing

- [ ] `swift test` passes locally
- [ ] If SDK-touching, `CONSAI_E2E=1 swift test` passes locally
- [ ] If UI-touching, screenshots regenerated under `docs/screenshots/`

## Screenshots / recordings

<!-- If user-visible. -->

## Notes for reviewer

<!-- Anything you want to call out — what to look at, what's deferred, what you weren't sure about. -->
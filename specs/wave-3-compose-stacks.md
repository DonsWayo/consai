# Wave 3 — Compose stacks in the panel

**Goal:** group containers into compose stacks, with up/down and a persistent project
registry. Surfaces the project's headline feature.

**Depends on:** Wave 2 (panel) + Wave 1 (`ComposeEngine`, `ProjectRegistry`).

## Deliverables

### Stack assembly into AppState
- On each poll, run `ProjectRegistry.assemble(containers:)` → `[Stack]` + standalone.
- `AppState` exposes `stacks: [Stack]` and `standalone: [Container]`.

### Panel UI — grouped
- Collapsible stack group header: `▸ myapp · 2/3 running` + status summary dot.
  - Header actions: `up` / `down`, restart-all, **reveal compose file** (Finder),
    open-in-editor (optional).
  - **Inferred stacks** (origin `.inferred`) visually marked (e.g. dashed/secondary tint
    + tooltip "not launched by Consai"); down/re-up disabled until a compose file is linked.
- Standalone containers listed under a "Containers" section below stacks.

### Compose actions
- `up`: file picker (or pick from **recent compose files**) → `ComposeEngine.up(file:)`
  → on success `ProjectRegistry.record(project, file)` → re-poll.
- `down`: only enabled when the stack has a known `composeFilePath`; runs
  `ComposeEngine.down(file:)`; **never** attempts destructive action on an inferred stack
  without a linked file.
- "Link compose file…" action on inferred stacks to promote them to known.

### Persistence
- `ProjectRegistry` persists `{ projectName → { composeFilePath, lastUp } }` + recent files
  list to JSON in `~/Library/Application Support/Consai/`.
- `container-compose` missing → stack up/down disabled with *"Install container-compose"*
  hint; existing groups still display (read-only). Raw container actions unaffected.

## Acceptance / tests
- `ProjectRegistry` persistence round-trip test.
- Assembly tests already in Wave 1; add AppState-level test that stacks/standalone are
  published correctly from a mock engine returning `<project>-<service>` names.
- Manual: `container-compose up` a sample stack from Consai; it appears grouped with the
  right running count; `down` tears it down; running `up` from a terminal shows as an
  inferred stack that self-heals into known after "Link compose file".

## Done when
- Stacks group correctly (known + inferred), up/down work, registry persists across launches,
  and destructive actions are gated on a known compose file.

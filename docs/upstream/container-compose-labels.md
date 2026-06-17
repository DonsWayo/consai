# DRAFT — upstream PR proposal for `Mcrich23/container-compose`

> **Status: draft, not submitted.** Prototyped locally; review before opening upstream.
> Origin: Consai persona QA found that containers can't be grouped into stacks reliably
> because `container-compose` writes no labels (see Consai issue #12 / PR #13).

## Proposed PR title
`Stamp com.docker.compose project/service labels on created containers`

## Proposed PR body

`container-compose up` currently names containers `<project>-<service>` but writes **no
labels** (`container inspect` shows `labels: {}`). External tools (GUIs, dashboards, scripts)
that want to group a stack's containers are forced to guess from the name prefix, which
mis-groups unrelated containers that merely share a prefix (e.g. `qa-web` + `qa-cache`).

This adds the de-facto-standard Docker Compose labels to each container at creation:

- `com.docker.compose.project=<project>`
- `com.docker.compose.service=<service>`

so any tool can group a stack reliably via `container inspect` labels, with zero behavior
change otherwise. (`container-compose down`/`ps` continue to work by name as before.)

## Diff (1 file, +9)

```diff
--- a/Sources/Container-Compose/Commands/ComposeUp.swift
+++ b/Sources/Container-Compose/Commands/ComposeUp.swift
@@ -449,6 +449,15 @@ public struct ComposeUp: AsyncParsableCommand, @unchecked Sendable {
         runCommandArgs.append("--name")
         runCommandArgs.append(containerName)
 
+        // Stamp Docker-Compose-compatible project/service labels so external tools (GUIs,
+        // dashboards) can group a stack's containers reliably by label, instead of guessing
+        // from the `<project>-<service>` name prefix (which mis-groups unrelated containers
+        // that merely share a prefix).
+        if let project = projectName {
+            runCommandArgs.append(contentsOf: ["--label", "com.docker.compose.project=\(project)"])
+        }
+        runCommandArgs.append(contentsOf: ["--label", "com.docker.compose.service=\(serviceName)"])
+
         // REMOVED: Restart policy is not supported by `container run`
```

## Test plan
1. `container-compose up -d --file docker-compose.yml`
2. `container inspect <project>-<service>` → `labels` contains
   `com.docker.compose.project` and `com.docker.compose.service`.
3. `container-compose down` still tears the stack down (name-based; unchanged).

## Notes / open questions for the maintainer
- Label *key* choice: `com.docker.compose.*` (Docker-compatible, broadest tool support) vs a
  project-specific namespace. Proposed the Docker keys for interoperability.
- Could also label the project network/volumes once per-project isolation lands.
- Not yet build-verified locally (trivial append to an existing `[String]` args array;
  `projectName`/`serviceName`/`runCommandArgs` are all in scope). Would `swift build` before submitting.

## What this unlocks in Consai
Consai could group **externally-launched** stacks reliably by reading
`com.docker.compose.project` from the container labels (we already map `configuration.labels`),
and safely re-enable grouping-by-default — removing the false-positive that PR #13 worked
around by making name-prefix inference opt-in.

# Security Policy

## Supported versions

Consai is in pre-release (v0.x). Only the latest tagged release receives
security updates.

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Reporting a vulnerability

**Please don't file a public issue for security vulnerabilities.**

Use [GitHub Security Advisories](https://github.com/DonsWayo/consai/security/advisories/new)
to report privately. You'll get a private thread with the maintainer and
a CVE can be coordinated through GitHub if the issue warrants it.

Include in your report:

- A clear description of the issue and its impact
- Reproduction steps (a container name, a CLI command, a UI path)
- The Consai version, macOS version, and `container` / `container-compose`
  versions involved
- Whether the issue is exploitable remotely, locally, or only with
  specific access (e.g. `container` service access)

## Response targets

- **Acknowledgement** within 72 hours
- **Triage and severity assessment** within 7 days
- **Fix or mitigation** timeline depends on severity:
  - Critical (RCE, container escape, privilege escalation): as fast as
    possible, usually within days
  - High (data loss, broad denial of service): within 2 weeks
  - Medium/Low: bundled into the next release

## Threat model in scope

Consai runs as an **LSUIElement agent** (no Dock icon), talks to:

- The local `container` system service over XPC (Apple's official Swift
  SDK, pinned to match the daemon — see [R1](CLAUDE.md))
- `container-compose` over `Process` spawn, if installed
- `Process` for log streaming and shell entry (R6 mitigates leaks)

Out of scope: the `container` daemon itself, `container-compose`, and
the host OS. Report those upstream.

## Hardening notes for self-builders

- **Always match the SDK pin in `Package.swift` to your installed daemon
  version.** A skew causes XPC wire-decoding errors at runtime — and may
  silently mask or corrupt responses. See [R1](CLAUDE.md).
- **Empty entitlements (`App/Consai.entitlements`)** are intentional.
  Consai is distributed outside the Mac App Store (R9) so it can reach
  XPC and spawn processes.
- **Don't run Consai from a Downloads-folder copy you didn't build
  yourself.** `swift run bundle` signs ad-hoc by default; for a
  notarized release use `swift run sign` with your Developer ID.
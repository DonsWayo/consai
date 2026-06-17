# Releasing Consai

Consai is distributed **outside the Mac App Store** (like Orchard) — it's non-sandboxed so
it can reach the `container` XPC daemon and spawn processes. That means releases must be
**code-signed with a Developer ID and notarized**, or Gatekeeper will block them.

> These steps require an Apple Developer account / Developer ID certificate, so they are
> run by a maintainer — not automated in CI. CI only runs the unit tests.

## 1. Build + bundle

```bash
scripts/bundle.sh release          # → Consai.app (arm64, ad-hoc signed)
```

## 2. Sign with Developer ID

```bash
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: <YOUR NAME> (<TEAMID>)" \
  Consai.app
codesign --verify --strict --verbose=2 Consai.app
```

`--options runtime` enables the hardened runtime (required for notarization).

## 3. Notarize + staple

```bash
ditto -c -k --keepParent Consai.app Consai.zip
xcrun notarytool submit Consai.zip \
  --apple-id "<APPLE_ID>" --team-id "<TEAMID>" --password "<APP_SPECIFIC_PASSWORD>" \
  --wait
xcrun stapler staple Consai.app
```

## 4. Distribute

- Zip the stapled app (or build a `.dmg`) and attach to a GitHub release.
- **Homebrew cask** (the expected install path for this ecosystem). Sketch:

```ruby
cask "consai" do
  version "0.1.0"
  sha256 "<sha256 of the zip>"
  url "https://github.com/DonsWayo/consai/releases/download/v#{version}/Consai.zip"
  name "Consai"
  desc "Menu-bar-first manager for Apple containers"
  homepage "https://github.com/DonsWayo/consai"
  depends_on macos: ">= :tahoe"          # macOS 26
  app "Consai.app"
end
```

## Outstanding before a public 0.1.0

- App icon (`AppIcon` asset) — not yet designed.
- A Developer ID certificate + the notarization secrets above.
- Decide repo home + cask tap.

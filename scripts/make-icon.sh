#!/usr/bin/env bash
# Render the Consai app icon and build AppIcon.icns (App/Resources/AppIcon.icns).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

swift build >/dev/null
PNG="$(mktemp -d)/icon.png"
.build/debug/Consai --render-icon "$PNG"

ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s        "$PNG" --out "$ICONSET/icon_${s}x${s}.png"   >/dev/null
  sips -z $((s*2)) $((s*2)) "$PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p "$ROOT/App/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/App/Resources/AppIcon.icns"
echo "✓ App/Resources/AppIcon.icns"

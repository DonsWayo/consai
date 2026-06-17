#!/usr/bin/env bash
# Build Consai with SwiftPM and assemble a runnable Consai.app bundle.
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ Building Consai ($CONFIG, arm64)…"
swift build -c "$CONFIG" --arch arm64

BIN="$ROOT/.build/release/Consai"
[ "$CONFIG" = debug ] && BIN="$ROOT/.build/debug/Consai"

APP="$ROOT/Consai.app"
echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Consai"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper/launch accepts it locally (real releases: Developer ID + notarize).
echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Run:  open '$APP'   (or: '$APP/Contents/MacOS/Consai')"

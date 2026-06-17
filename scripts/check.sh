#!/usr/bin/env bash
# Local pre-flight check — build + test the pure logic tier. Run this before pushing
# instead of relying on CI (this project builds and tests entirely on the developer's
# macOS 26 / Xcode 26 machine; Apple's `container` SDK can't build on hosted runners).
#
#   scripts/check.sh            # build + test
#   scripts/check.sh coverage   # build + test + print logic-tier coverage report
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift --version"
swift --version

echo "==> swift build"
swift build

if [[ "${1:-}" == "coverage" ]]; then
  echo "==> swift test --enable-code-coverage"
  swift test --enable-code-coverage
  PROF=$(find .build -name default.profdata | head -1)
  BIN=$(find .build -name ConsaiPackageTests -type f | head -1)
  echo "==> coverage (logic layers)"
  xcrun llvm-cov report "$BIN" -instr-profile "$PROF" \
    ConsaiCore/Sources ConsaiKit/Sources | grep -vE "Tests/|MockEngines"
else
  echo "==> swift test"
  swift test
fi

echo "==> OK"

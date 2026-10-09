#!/bin/sh
# Builds WriteMD.app (ad-hoc signed, no Apple Developer account needed) into build/Build/Products/<config>/.
# Usage: scripts/build.sh [Debug|Release]      Run tests with: scripts/build.sh test
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)"; exit 1; }
xcodegen generate --quiet

if [ "$1" = "test" ]; then
  xcodebuild -project WriteMD.xcodeproj -scheme WriteMD -configuration Debug -derivedDataPath build test
  exit 0
fi

CONFIG="${1:-Release}"
xcodebuild -project WriteMD.xcodeproj -scheme WriteMD -configuration "$CONFIG" -derivedDataPath build build
echo "==> $ROOT/build/Build/Products/$CONFIG/WriteMD.app"

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp "${TMPDIR:-/tmp}/splainit-vision.XXXXXX")
trap 'rm -f "$test_binary"' EXIT HUP INT TERM
xcrun clang -fobjc-arc -Wall -Wextra -mmacosx-version-min=14.0 \
  -framework AppKit -framework Vision -framework CoreText \
  src-tauri/src/macos/visual.m src-tauri/tests/vision_smoke.m -o "$test_binary"
"$test_binary"

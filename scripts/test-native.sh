#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp "${TMPDIR:-/tmp}/splainit-resolver.XXXXXX")
trap 'rm -f "$test_binary"' EXIT HUP INT TERM
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Foundation src-tauri/src/macos/resolver.m \
  src-tauri/tests/resolver_tests.m -o "$test_binary"
"$test_binary"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -framework Foundation -framework AppKit -framework Vision \
  src-tauri/src/macos/visual.m src-tauri/tests/visual_tests.m -o "$test_binary"
"$test_binary"

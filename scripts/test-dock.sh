#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-dock-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Services/DockWindowMatching.swift" \
  "$ROOT/Tests/DockWindows/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"

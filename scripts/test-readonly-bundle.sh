#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -eq 1 ] || { printf 'Usage: %s UNIVERSAL_APP_DMG\n' "$0" >&2; exit 2; }
TEST_DIR=$(mktemp -d /tmp/autoproductive-readonly-test.XXXXXX)
MOUNTED=0
cleanup() { if [ "$MOUNTED" = 1 ]; then hdiutil detach "$TEST_DIR/mount" >/dev/null; fi; rm -rf "$TEST_DIR"; }
trap cleanup EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureArchitecture.swift" \
  "$ROOT/AutoProductive/Services/AppArchitectureThinner.swift" \
  "$ROOT/Tests/ReadOnlyBundle/main.swift" -o "$TEST_DIR/test"
mkdir "$TEST_DIR/mount"
hdiutil attach -readonly -nobrowse -mountpoint "$TEST_DIR/mount" "$1" >/dev/null
MOUNTED=1
"$TEST_DIR/test" "$TEST_DIR/mount/AutoProductive.app"

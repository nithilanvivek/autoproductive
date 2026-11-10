#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-relaunch-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureArchitecture.swift" \
  "$ROOT/AutoProductive/Services/AppArchitectureThinner.swift" \
  "$ROOT/AutoProductive/Services/ApplicationRelauncher.swift" \
  "$ROOT/Tests/ApplicationRelauncher/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"

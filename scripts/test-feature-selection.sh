#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-selection.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/FeatureSelectionState.swift" \
  "$ROOT/Tests/FeatureSelection/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"

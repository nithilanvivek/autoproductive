#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-update-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Models/UpdateSchedule.swift" \
  "$ROOT/Tests/UpdateSchedule/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"

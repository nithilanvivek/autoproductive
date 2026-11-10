#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-closed-lid.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Services/ExitRecoveryWatchdog.swift" \
  "$ROOT/AutoProductive/Services/ClosedLidPowerControl.swift" \
  "$ROOT/Tests/ClosedLid/main.swift" -o "$TEST_DIR/tests" -framework IOKit
"$TEST_DIR/tests"

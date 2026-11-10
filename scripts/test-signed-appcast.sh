#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-appcast-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swift -module-cache-path "$TEST_DIR/cache" "$ROOT/Tests/SignedAppcast/main.swift" "$ROOT/../autoproductive/appcast.xml" "$ROOT/AutoProductive/Info.plist"

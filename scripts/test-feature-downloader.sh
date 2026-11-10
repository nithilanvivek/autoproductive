#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/autoproductive-download.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Services/FeaturePackageDownloader.swift" \
  "$ROOT/Tests/FeatureDownloader/main.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests"

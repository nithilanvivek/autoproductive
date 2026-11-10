#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${AUTOPRODUCTIVE_SIGN_IDENTITY:?Set AUTOPRODUCTIVE_SIGN_IDENTITY to the app signing identity}"
TEST_DIR=$(mktemp -d /tmp/autoproductive-awake-test.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
sh "$ROOT/scripts/build-keep-awake-assertions.sh" "$TEST_DIR/keepAwake.dylib"
xcrun swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$ROOT/AutoProductive/Services/FeatureToolLibrary.swift" \
  "$ROOT/AutoProductive/Services/FeatureKeepAwakeAssertions.swift" \
  "$ROOT/Tests/KeepAwakeAssertionComponent/main.swift" -o "$TEST_DIR/tests"
codesign --force --sign "$AUTOPRODUCTIVE_SIGN_IDENTITY" --options runtime "$TEST_DIR/tests" >/dev/null 2>&1
"$TEST_DIR/tests" "$TEST_DIR/keepAwake.dylib"
